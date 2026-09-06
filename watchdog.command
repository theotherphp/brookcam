#!/bin/bash
# Double-clickable wrapper that runs watchdog.sh inside Terminal.app.
#
# This is the route that works on the mini (see SETUP.md). Add this file to
# System Settings > General > Login Items and macOS opens it in Terminal.app
# at login. That matters because Local Network permission is granted to the
# *responsible* app, per binary: under Terminal.app, ffmpeg inherits the grant
# that already works. Launched by launchd it does not, and the camera comes
# back as "No route to host".
# See run.command for the full explanation.
cd "$(dirname "$0")" || exit 1

# Tee to the same log the launchd agents used, so output is both visible in
# the window and greppable afterwards. Truncate if it has grown past ~50MB.
LOG="$HOME/Library/Logs/brookcam-watchdog.log"
mkdir -p "$(dirname "$LOG")"
if [[ -f "$LOG" && $(stat -f%z "$LOG") -gt 52428800 ]]; then
  : > "$LOG"
fi

./watchdog.sh 2>&1 | tee -a "$LOG"
