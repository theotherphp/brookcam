#!/bin/bash
# One-shot health report for the mini. Run it in a GUI Terminal (Screen
# Sharing), not over ssh — an ssh session has a different permission context.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$HOME/Library/Logs/brookcam.log"

echo "=== now ==="
date
echo "uptime:$(uptime | sed 's/.*up//; s/,.*users.*//')"
echo

echo "=== processes ==="
pgrep -fl 'run\.sh|watchdog\.sh' || echo "  run.sh / watchdog.sh NOT running"
if pgrep -x ffmpeg > /dev/null; then
  echo "  ffmpeg running (pid $(pgrep -x ffmpeg | tr '\n' ' '))"
else
  echo "  ffmpeg NOT running"
fi
echo

echo "=== conflict check ==="
# Both mechanisms at once means two run.sh loops fighting over one stream key.
if launchctl list 2> /dev/null | grep -q com.brookcam; then
  echo "  WARNING: launchd agents are ALSO loaded:"
  launchctl list | grep com.brookcam | sed 's/^/    /'
  echo "  Run ./install-launchd.sh uninstall if you are using Login Items."
else
  echo "  no launchd agents loaded (expected for the Login Items route)"
fi
n=$(pgrep -f 'run\.sh' | wc -l | tr -d ' ')
[[ "$n" -gt 1 ]] && echo "  WARNING: $n copies of run.sh are running"
echo

echo "=== last 15 log lines ($LOG) ==="
if [[ -f "$LOG" ]]; then
  echo "  last written: $(stat -f '%Sm' "$LOG")"
  tail -15 "$LOG" | sed 's/^/  /'
else
  echo "  no log file — the wrappers have not written anything"
fi
echo

echo "=== live camera probe from this Terminal ==="
"$SCRIPT_DIR/check-camera.sh"
