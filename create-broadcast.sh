#!/bin/bash
# Create a fresh YouTube broadcast for today with autoStart enabled.
# Called by run.sh once per day before starting ffmpeg.
#
# Requires in brookcam.env:
#   YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN
#   YOUTUBE_STREAM_KEY (used to identify the persistent stream)
#   YOUTUBE_BROADCAST_PRIVACY (optional, default: public)
#
# Prerequisites: brew install jq

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_PATH=~/brookcam/brookcam.env
if [[ ! -f "$ENV_PATH" ]]; then
  echo "env file not found: $ENV_PATH"
  exit 1
fi
source "$ENV_PATH"

API_BASE="https://www.googleapis.com/youtube/v3"
TODAY=$(date +"%a %b %-d, %Y")           # e.g. "Wed Mar 4, 2026"
BROADCAST_TITLE="Brookcam - $TODAY"
PRIVACY="${YOUTUBE_BROADCAST_PRIVACY:-public}"

# --- Refresh access token ---

echo "Refreshing access token..."

TOKEN_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "client_id=$YOUTUBE_CLIENT_ID" \
  -d "client_secret=$YOUTUBE_CLIENT_SECRET" \
  -d "refresh_token=$YOUTUBE_REFRESH_TOKEN" \
  -d "grant_type=refresh_token")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Error: Failed to refresh access token."
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

auth_header="Authorization: Bearer $ACCESS_TOKEN"

# --- Check for existing broadcast today ---

echo "Checking for existing broadcast: $BROADCAST_TITLE"

# Check both upcoming and active broadcasts
for STATUS in upcoming active; do
  EXISTING=$(curl -s -G "$API_BASE/liveBroadcasts" \
    -H "$auth_header" \
    --data-urlencode "part=snippet" \
    --data-urlencode "broadcastStatus=$STATUS" \
    --data-urlencode "maxResults=50")

  MATCH=$(echo "$EXISTING" | jq -r \
    --arg title "$BROADCAST_TITLE" \
    '.items[]? | select(.snippet.title == $title) | .id' | head -1)

  if [[ -n "$MATCH" ]]; then
    echo "Broadcast already exists ($STATUS): $MATCH"
    echo "Skipping creation."
    exit 0
  fi
done

# --- Get the persistent stream ID ---

echo "Looking up stream..."

STREAMS_RESPONSE=$(curl -s -G "$API_BASE/liveStreams" \
  -H "$auth_header" \
  --data-urlencode "part=id,snippet,cdn" \
  --data-urlencode "mine=true" \
  --data-urlencode "maxResults=50")

# Find the stream — prefer matching by stream key, fall back to first stream
STREAM_ID=$(echo "$STREAMS_RESPONSE" | jq -r \
  --arg key "$YOUTUBE_STREAM_KEY" \
  '[.items[]? | select(.cdn.ingestionInfo.streamName == $key)] | .[0].id // empty')

if [[ -z "$STREAM_ID" ]]; then
  # Fall back to first available stream
  STREAM_ID=$(echo "$STREAMS_RESPONSE" | jq -r '.items[0].id // empty')
fi

if [[ -z "$STREAM_ID" ]]; then
  echo "Error: No live streams found on this channel."
  echo "Create a stream in YouTube Studio first, or check your credentials."
  exit 1
fi

echo "Using stream: $STREAM_ID"

# --- Create broadcast ---

# Schedule start a few minutes from now (YouTube requires a future time)
SCHEDULED_START=$(date -u -v+2M +"%Y-%m-%dT%H:%M:%SZ")

echo "Creating broadcast: $BROADCAST_TITLE"

BROADCAST_RESPONSE=$(curl -s -X POST "$API_BASE/liveBroadcasts?part=snippet,contentDetails,status" \
  -H "$auth_header" \
  -H "Content-Type: application/json" \
  -d "$(cat <<EOF
{
  "snippet": {
    "title": "$BROADCAST_TITLE",
    "scheduledStartTime": "$SCHEDULED_START"
  },
  "contentDetails": {
    "enableAutoStart": true,
    "enableAutoStop": true,
    "enableDvr": false
  },
  "status": {
    "privacyStatus": "$PRIVACY",
    "selfDeclaredMadeForKids": false,
    "embeddable": true
  }
}
EOF
)")

BROADCAST_ID=$(echo "$BROADCAST_RESPONSE" | jq -r '.id // empty')

if [[ -z "$BROADCAST_ID" ]]; then
  echo "Error: Failed to create broadcast."
  echo "Response: $BROADCAST_RESPONSE"
  exit 1
fi

echo "Created broadcast: $BROADCAST_ID"

# --- Bind broadcast to stream ---

echo "Binding broadcast to stream..."

BIND_RESPONSE=$(curl -s -X POST \
  "$API_BASE/liveBroadcasts/bind?id=$BROADCAST_ID&part=id,contentDetails&streamId=$STREAM_ID" \
  -H "$auth_header" \
  -H "Content-Type: application/json")

BIND_ID=$(echo "$BIND_RESPONSE" | jq -r '.id // empty')

if [[ -z "$BIND_ID" ]]; then
  echo "Error: Failed to bind broadcast to stream."
  echo "Response: $BIND_RESPONSE"
  exit 1
fi

echo "Broadcast $BROADCAST_ID bound to stream $STREAM_ID"
echo "Title: $BROADCAST_TITLE"
echo "Privacy: $PRIVACY"
echo "AutoStart: enabled — YouTube will go live when it detects RTMP input."
