#!/bin/bash
# Usage: ./run.sh         Start brookcam (Ctrl-C to stop)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echots() { echo "$*" | ts '[%Y-%m-%d %H:%M:%S %Z]'; }

while true; do
  echots "Creating broadcast..."
  if bash "$SCRIPT_DIR/create-broadcast.sh"; then
    echots "Broadcast ready, waiting 5s for YouTube to process..."
    sleep 5
  else
    echots "WARNING: Broadcast creation failed, continuing anyway"
  fi

  start=$(date +%s)
  bash "$SCRIPT_DIR/brookcam.sh"
  elapsed=$(( $(date +%s) - start ))

  if [[ $elapsed -lt 30 ]]; then
    echots "Stream exited after ${elapsed}s (camera down?), retrying in 5m..."
    sleep 300
  else
    echots "Stream exited after ${elapsed}s, restarting in 30s..."
    sleep 30
  fi
done
