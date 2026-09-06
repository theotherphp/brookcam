#!/bin/bash
# Double-clickable wrapper that runs run.sh inside Terminal.app.
#
# This is the route that works on the mini (see SETUP.md). Add this file to
# System Settings > General > Login Items and macOS opens it in Terminal.app
# at login. That matters because Local Network permission is granted to the
# *responsible* app, per binary: under Terminal.app, ffmpeg inherits the grant
# that already works. Launched by launchd it does not, and the camera comes
# back as "No route to host".

cd "$(dirname "$0")" || exit 1

LOG="$HOME/Library/Logs/brookcam.log"
mkdir -p "$(dirname "$LOG")"
# Truncate if it has grown past ~50MB. Note the log contains the RTSP URL,
# credentials included, so it is not safe to share as-is.
if [[ -f "$LOG" && $(stat -f%z "$LOG") -gt 52428800 ]]; then
  : > "$LOG"
fi

# ffmpeg echoes the full input URL on every error, and the output URL carries
# the YouTube stream key. Strip both before anything is written to disk or the
# screen — otherwise the camera password ends up in the log, and in any log you
# paste while asking someone for help. -l keeps sed line-buffered so tail -f
# still works live.
redact() {
  sed -l -E 's|(rtsp://[^:/@]+):[^@]+@|\1:REDACTED@|g; s|(rtmp://[^ ]*/live2/)[^ ]*|\1REDACTED|g'
}

main() {
  # Login Items fire before WiFi/Ethernet is up. Without this wait the first
  # attempt fails instantly and run.sh treats a sub-30s exit as a network
  # problem and sleeps 5 minutes — turning a reboot into a 5 minute outage.
  for i in $(seq 1 90); do
    if curl -s -o /dev/null -m 3 https://www.googleapis.com/generate_204; then
      [[ $i -gt 1 ]] && echo "network up after $(( i * 2 ))s" | ts '[%Y-%m-%d %H:%M:%S %Z]'
      break
    fi
    [[ $i -eq 1 ]] && echo "waiting for network..." | ts '[%Y-%m-%d %H:%M:%S %Z]'
    sleep 2
  done

  ./run.sh
}

main 2>&1 | redact | tee -a "$LOG"
