#!/bin/bash
# Usage: ./run.sh         Start (or restart) brookcam
#        ./run.sh stop    Stop brookcam

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIDFILE="/tmp/brookcam.pid"

stop() {
  if [[ -f "$PIDFILE" ]]; then
    PID=$(cat "$PIDFILE")
    kill "$PID" 2>/dev/null
    # Wait briefly for clean shutdown
    for i in 1 2 3; do
      kill -0 "$PID" 2>/dev/null || break
      sleep 1
    done
    rm -f "$PIDFILE"
  fi
  pkill -f "watchdog.sh" 2>/dev/null || true
  pkill -x ffmpeg 2>/dev/null || true
}

if [[ "$1" == "stop" ]]; then
  stop
  echo "Brookcam stopped."
  exit 0
fi

# Start (or restart)
stop
sleep 1

# Main loop runs in a background subshell
(
  # Clean up children on exit
  trap 'pkill -f watchdog.sh 2>/dev/null; pkill -x ffmpeg 2>/dev/null; rm -f "$PIDFILE"' EXIT
  echo "$BASHPID" > "$PIDFILE"

  # Start watchdog
  bash "$SCRIPT_DIR/watchdog.sh" >> /tmp/brookcam-watchdog.log 2>&1 &

  # Stream loop: restart on failure during operating hours, sleep overnight
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

sleep 0.5
echo "Brookcam started (PID $(cat "$PIDFILE"))"
echo "  Logs: tail -f /tmp/brookcam.log"
echo "  Stop: $0 stop"
