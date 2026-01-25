#!/bin/sh
# Simple watchdog: check if YouTube stream is live, restart ffmpeg if not

ENV_PATH="./brookcam.env"
if [[ ! -f "$ENV_PATH" ]]; then
  echo "env file not found"
  exit 1
fi
source $ENV_PATH

# Requires: YOUTUBE_VIDEO_ID, PUSHOVER_USER_KEY, PUSHOVER_APP_TOKEN in env

POLL_INTERVAL=300

notify() {
  curl -s \
    --form-string "token=$PUSHOVER_APP_TOKEN" \
    --form-string "user=$PUSHOVER_USER_KEY" \
    --form-string "message=$1" \
    https://api.pushover.net/1/messages.json > /dev/null
}

check_live() {
  yt-dlp --skip-download --print "%(is_live)s" \
    "https://www.youtube.com/watch?v=$YOUTUBE_VIDEO_ID" 2>/dev/null
}

echo "Watchdog started $(date +"%a %x at %r")"

while true; do
  sleep $POLL_INTERVAL

  is_live=$(check_live)

  if [ "$is_live" != "True" ]; then
    echo "Stream down at $(date +"%r"), restarting ffmpeg"
    notify "Brookcam stream down, restarting ffmpeg"
    pkill -x ffmpeg
  fi
done
