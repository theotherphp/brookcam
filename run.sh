#!/bin/bash
# Usage: ./run.sh         Start brookcam (Ctrl-C to stop)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while true; do
  echo "Creating broadcast..."
  if bash "$SCRIPT_DIR/create-broadcast.sh"; then
    echo "Broadcast ready, waiting 5s for YouTube to process..."
    sleep 5
  else
    echo "WARNING: Broadcast creation failed, continuing anyway"
  fi

  start=$(date +%s)
  bash "$SCRIPT_DIR/brookcam.sh"
  elapsed=$(( $(date +%s) - start ))

  if [[ $elapsed -lt 30 ]]; then
    echo "Stream exited after ${elapsed}s (camera down?), retrying in 5m..."
    sleep 300
  else
    echo "Stream exited after ${elapsed}s, restarting in 30s..."
    sleep 30
  fi
done 2>&1 | ts '[%Y-%m-%d %H:%M:%S %Z]'
