#!/bin/sh
# Watchdog with proactive stall detection
# Monitors ffmpeg progress file to detect stalls BEFORE YouTube notices

ENV_PATH="./brookcam.env"
if [[ ! -f "$ENV_PATH" ]]; then
  echo "env file not found"
  exit 1
fi
source $ENV_PATH

# Requires: YOUTUBE_CHANNEL_ID, PUSHOVER_USER_KEY, PUSHOVER_APP_TOKEN in env

POLL_INTERVAL=60          # Check every 60 seconds
STALL_THRESHOLD=120       # Stall if progress file unchanged for 2 minutes
PROGRESS_FILE="/tmp/brookcam_progress"

notify() {
  curl -s \
    --form-string "token=$PUSHOVER_APP_TOKEN" \
    --form-string "user=$PUSHOVER_USER_KEY" \
    --form-string "message=$1" \
    https://api.pushover.net/1/messages.json > /dev/null
}

check_live() {
  yt-dlp --skip-download --print "%(is_live)s" \
    "https://www.youtube.com/embed/live_stream?channel=$YOUTUBE_CHANNEL_ID" 2>/dev/null
}

# Get frame count from progress file
get_frame_count() {
  if [[ -f "$PROGRESS_FILE" ]]; then
    grep "^frame=" "$PROGRESS_FILE" | tail -1 | cut -d= -f2
  else
    echo "0"
  fi
}

# Get progress file modification time (seconds since epoch)
get_progress_mtime() {
  if [[ -f "$PROGRESS_FILE" ]]; then
    stat -f %m "$PROGRESS_FILE" 2>/dev/null || echo "0"
  else
    echo "0"
  fi
}

echo "Watchdog started $(date +"%a %x at %r")"
echo "Monitoring progress file: $PROGRESS_FILE"
echo "Stall threshold: ${STALL_THRESHOLD}s"

last_frame_count=0

while true; do
  sleep $POLL_INTERVAL

  now=$(date +%s)
  progress_mtime=$(get_progress_mtime)
  current_frame_count=$(get_frame_count)
  file_age=$((now - progress_mtime))

  # Proactive check 1: Progress file not being updated
  if [[ $file_age -gt $STALL_THRESHOLD ]]; then
    echo "STALL DETECTED: Progress file not updated for ${file_age}s at $(date +"%r")"
    notify "Brookcam stall: progress file stale (${file_age}s), restarting"
    pkill -x ffmpeg
    last_frame_count=0
    continue
  fi

  # Proactive check 2: Frame count not advancing
  if [[ "$current_frame_count" == "$last_frame_count" && "$current_frame_count" != "0" ]]; then
    echo "STALL DETECTED: Frame count stuck at $current_frame_count at $(date +"%r")"
    notify "Brookcam stall: frames stuck at $current_frame_count, restarting"
    pkill -x ffmpeg
    last_frame_count=0
    continue
  fi

  last_frame_count=$current_frame_count

  # Fallback check: YouTube reports stream down (slower but authoritative)
  is_live=$(check_live)
  if [[ "$is_live" != "True" ]]; then
    echo "Stream down per YouTube at $(date +"%r"), restarting ffmpeg"
    notify "Brookcam: YouTube reports down, restarting"
    pkill -x ffmpeg
    last_frame_count=0
  fi
done
