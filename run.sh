#!/bin/bash
# Usage: ./run.sh         Start brookcam (Ctrl-C to stop)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while true; do
  echo "$(date): Creating broadcast..."
  if bash "$SCRIPT_DIR/create-broadcast.sh"; then
    echo "$(date): Broadcast ready, waiting 5s for YouTube to process..."
    sleep 5
  else
    echo "$(date): WARNING: Broadcast creation failed, continuing anyway"
  fi

  start=$(date +%s)
  bash "$SCRIPT_DIR/brookcam.sh"
  elapsed=$(( $(date +%s) - start ))

  if [[ $elapsed -lt 30 ]]; then
    echo "$(date): Stream exited after ${elapsed}s (camera down?), retrying in 5m..."
    sleep 300
  else
    echo "$(date): Stream exited after ${elapsed}s, restarting in 30s..."
    sleep 30
  fi
done
