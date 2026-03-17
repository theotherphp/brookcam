#!/bin/bash
# One-time setup: Exchange Google OAuth credentials for a refresh token
# and save YouTube API credentials to brookcam.env.
#
# Usage: ./setup-oauth.sh path/to/client_secret_*.json
#
# Prerequisites:
#   - brew install jq
#   - A Google Cloud project with YouTube Data API v3 enabled
#   - OAuth Desktop app credentials downloaded as JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/brookcam.env"
REDIRECT_URI="http://127.0.0.1:8085"
SCOPE="https://www.googleapis.com/auth/youtube"

# --- Validate inputs ---

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/client_secret_*.json"
  exit 1
fi

CLIENT_SECRET_FILE="$1"

if [[ ! -f "$CLIENT_SECRET_FILE" ]]; then
  echo "Error: File not found: $CLIENT_SECRET_FILE"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

# --- Extract credentials from Google's JSON format ---

# Google uses "installed" key for Desktop app credentials
CLIENT_ID=$(jq -r '.installed.client_id // empty' "$CLIENT_SECRET_FILE")
CLIENT_SECRET=$(jq -r '.installed.client_secret // empty' "$CLIENT_SECRET_FILE")

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" ]]; then
  echo "Error: Could not extract client_id/client_secret from $CLIENT_SECRET_FILE"
  echo "       Make sure this is a Desktop app credential (has 'installed' key)."
  exit 1
fi

echo "Client ID: ${CLIENT_ID:0:20}..."
echo ""

# --- Build OAuth URL and get authorization code ---

AUTH_URL="https://accounts.google.com/o/oauth2/v2/auth"
AUTH_URL+="?client_id=$CLIENT_ID"
AUTH_URL+="&redirect_uri=$REDIRECT_URI"
AUTH_URL+="&response_type=code"
AUTH_URL+="&scope=$SCOPE"
AUTH_URL+="&access_type=offline"
AUTH_URL+="&prompt=consent"

echo "Opening browser for Google authorization..."
echo ""
open "$AUTH_URL" 2>/dev/null || echo "Open this URL in your browser: $AUTH_URL"
echo ""
echo "After authorizing, your browser will redirect to a localhost URL."
echo "It will show an error page — that's expected."
echo ""
echo "Copy the FULL URL from your browser's address bar and paste it here:"
echo "(It will look like: http://127.0.0.1:8085/?code=4/0A...&scope=...)"
echo ""
read -r REDIRECT_RESPONSE

# Extract the authorization code from the pasted URL
AUTH_CODE=$(echo "$REDIRECT_RESPONSE" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')

if [[ -z "$AUTH_CODE" ]]; then
  echo "Error: Could not extract authorization code from the URL you pasted."
  echo "       Make sure you copied the full URL from the browser address bar."
  exit 1
fi

echo ""
echo "Authorization code received. Exchanging for tokens..."

# --- Exchange authorization code for tokens ---

TOKEN_RESPONSE=$(curl -s -X POST "https://oauth2.googleapis.com/token" \
  -d "code=$AUTH_CODE" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "redirect_uri=$REDIRECT_URI" \
  -d "grant_type=authorization_code")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.refresh_token // empty')

if [[ -z "$ACCESS_TOKEN" || -z "$REFRESH_TOKEN" ]]; then
  echo "Error: Token exchange failed."
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "Tokens received."
echo ""

# --- Validate with a test API call ---

echo "Validating credentials with a test API call..."

CHANNEL_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://www.googleapis.com/youtube/v3/channels?part=snippet&mine=true")

CHANNEL_TITLE=$(echo "$CHANNEL_RESPONSE" | jq -r '.items[0].snippet.title // empty')

if [[ -z "$CHANNEL_TITLE" ]]; then
  echo "Warning: Could not retrieve channel info. Response:"
  echo "$CHANNEL_RESPONSE"
  echo ""
  echo "The tokens may still be valid. Continuing..."
else
  echo "Authenticated as YouTube channel: $CHANNEL_TITLE"
fi

echo ""

# --- Save to brookcam.env ---

# Remove any existing YouTube OAuth lines
if [[ -f "$ENV_FILE" ]]; then
  # Create a temp file without the old OAuth lines
  grep -v '^YOUTUBE_CLIENT_ID=' "$ENV_FILE" | \
    grep -v '^YOUTUBE_CLIENT_SECRET=' | \
    grep -v '^YOUTUBE_REFRESH_TOKEN=' | \
    grep -v '^YOUTUBE_BROADCAST_PRIVACY=' > "$ENV_FILE.tmp" || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
fi

cat >> "$ENV_FILE" <<EOF
YOUTUBE_CLIENT_ID=$CLIENT_ID
YOUTUBE_CLIENT_SECRET=$CLIENT_SECRET
YOUTUBE_REFRESH_TOKEN=$REFRESH_TOKEN
YOUTUBE_BROADCAST_PRIVACY=public
EOF

echo "Credentials saved to $ENV_FILE"
echo ""
echo "Setup complete! You can now run create-broadcast.sh to test."
echo ""
echo "To change broadcast privacy, edit YOUTUBE_BROADCAST_PRIVACY in $ENV_FILE"
echo "  Options: public, unlisted, private"
