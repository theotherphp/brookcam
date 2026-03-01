#!/bin/bash
# Start brookcam stream and watchdog in the background
# Run from an interactive shell: ./run.sh
# Logs to /tmp/brookcam.log, /tmp/brookcam-watchdog.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Kill any existing brookcam processes
pkill -x ffmpeg 2>/dev/null || true
pkill -f "brookcam.sh" 2>/dev/null || true
pkill -f "watchdog.sh" 2>/dev/null || true
sleep 1

# Stream loop: restart on failure during operating hours, sleep overnight
(
  while true; do
    HOUR=$(date +%-H)
    if [[ $HOUR -ge 6 && $HOUR -lt 20 ]]; then
      bash "$SCRIPT_DIR/brookcam.sh"
      echo "$(date): Stream exited, restarting in 30s..."
      sleep 30
    else
      echo "$(date): Outside operating hours, sleeping 5m..."
      sleep 300
    fi
  done
) >> /tmp/brookcam.log 2>&1 &
STREAM_PID=$!

# Watchdog loop: same pattern
(
  while true; do
    HOUR=$(date +%-H)
    if [[ $HOUR -ge 6 && $HOUR -lt 20 ]]; then
      bash "$SCRIPT_DIR/watchdog.sh"
      echo "$(date): Watchdog exited, restarting in 30s..."
      sleep 30
    else
      sleep 300
    fi
  done
) >> /tmp/brookcam-watchdog.log 2>&1 &
WATCHDOG_PID=$!

echo "Brookcam started:"
echo "  Stream wrapper PID:   $STREAM_PID"
echo "  Watchdog wrapper PID: $WATCHDOG_PID"
echo ""
echo "Logs:"
echo "  tail -f /tmp/brookcam.log"
echo "  tail -f /tmp/brookcam-watchdog.log"
echo ""
echo "Stop with: pkill -f brookcam"
