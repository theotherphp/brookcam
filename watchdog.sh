#!/bin/bash
# Watchdog: polls YouTube every 60s and restarts ffmpeg if the stream is down

ENV_PATH=~/brookcam/brookcam.env
if [[ ! -f "$ENV_PATH" ]]; then
  echo "env file not found"
  exit 1
fi
source "$ENV_PATH"

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

consecutive_failures=0

echo "Watchdog started"

while true; do
  sleep 60

  if [[ "$(check_live)" != "True" ]]; then
    consecutive_failures=$(( consecutive_failures + 1 ))
    echo "Stream down per YouTube (failure $consecutive_failures), restarting ffmpeg"
    if [[ $consecutive_failures -ge 3 ]]; then
      notify "Brookcam: stream down $consecutive_failures checks in a row, restarting"
    fi
    pkill -x ffmpeg
  else
    consecutive_failures=0
  fi
done 2>&1 | ts '[%Y-%m-%d %H:%M:%S %Z]'
