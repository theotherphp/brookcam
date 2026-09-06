#!/bin/bash
# Diagnose why ffmpeg cannot open the camera.
#
#   ./check-camera.sh             probe from this shell
#   ./check-camera.sh --as-agent  probe from a throwaway LaunchAgent
#
# The point is the comparison. Run it both ways in a GUI Terminal (Screen
# Sharing, not ssh). If the direct run reaches the camera and the --as-agent
# run does not, the difference is macOS Local Network privacy, because
# nothing else about the two runs differs. If both fail the same way, the
# problem is the network or the camera, and launchd is innocent.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" == "--as-agent" ]]; then
  LABEL=com.brookcam.probe
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  LOG="$HOME/Library/Logs/brookcam-probe.log"
  DOMAIN="gui/$(id -u)"

  if command -v brew > /dev/null 2>&1; then BREW_BIN="$(brew --prefix)/bin"; else BREW_BIN=/opt/homebrew/bin; fi

  rm -f "$LOG"
  cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key><string>$LABEL</string>
	<key>ProgramArguments</key>
	<array><string>/bin/bash</string><string>$SCRIPT_DIR/check-camera.sh</string></array>
	<key>WorkingDirectory</key><string>$SCRIPT_DIR</string>
	<key>EnvironmentVariables</key>
	<dict><key>PATH</key><string>$BREW_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
	<key>RunAtLoad</key><true/>
	<key>LimitLoadToSessionType</key><string>Aqua</string>
	<key>StandardOutPath</key><string>$LOG</string>
	<key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
PLIST

  launchctl bootout "$DOMAIN/$LABEL" 2> /dev/null
  launchctl bootstrap "$DOMAIN" "$PLIST" || { echo "could not load probe agent"; exit 1; }

  echo "Running probe as a LaunchAgent..."
  for _ in $(seq 1 30); do
    sleep 1
    launchctl print "$DOMAIN/$LABEL" 2> /dev/null | grep -q "state = running" || break
  done
  sleep 1

  echo "----- output from the LaunchAgent -----"
  cat "$LOG" 2> /dev/null || echo "(no output — the agent produced nothing)"
  echo "--------------------------------------"

  launchctl bootout "$DOMAIN/$LABEL" 2> /dev/null
  rm -f "$PLIST"
  exit 0
fi

ENV_PATH="$SCRIPT_DIR/brookcam.env"
[[ -f "$ENV_PATH" ]] || ENV_PATH=~/brookcam/brookcam.env
if [[ ! -f "$ENV_PATH" ]]; then
  echo "FAIL: env file not found ($ENV_PATH)"
  exit 1
fi
source "$ENV_PATH"

echo "context : uid=$(id -u) user=$(id -un) HOME=$HOME"
echo "ffmpeg  : $(command -v ffmpeg || echo 'NOT FOUND — check PATH')"
echo "camera  : $CAMERA_IP:554"
echo

# 1. Internet. NOT a local address, so Local Network privacy does not apply.
if curl -s -o /dev/null -m 8 https://www.googleapis.com/generate_204; then
  internet=ok
else
  internet=fail
fi
echo "internet: $internet"

# 2. Plain TCP to the camera's RTSP port. This IS a local address, so it is
#    exactly what Local Network privacy gates.
if nc -z -G 4 -w 4 "$CAMERA_IP" 554 2> /dev/null; then
  lan=ok
else
  lan=fail
fi
echo "lan tcp : $lan"

# 3. The real thing.
probe_out=$(ffprobe -v error -rtsp_transport tcp -timeout 8000000 \
  -show_entries stream=codec_name,width,height -of default=nw=1 \
  "rtsp://$CAMERA_USER:$CAMERA_PASSWORD@$CAMERA_IP:554/h264Preview_01_sub" 2>&1)
probe_rc=$?
if [[ $probe_rc -eq 0 ]]; then
  echo "rtsp    : ok"
else
  echo "rtsp    : fail"
fi
echo

echo "=== diagnosis ==="
if [[ $probe_rc -eq 0 ]]; then
  echo "Camera opens fine from this context."
  echo "$probe_out" | sed 's/^/  /'
elif [[ "$internet" == ok && "$lan" == fail ]]; then
  echo "The internet is reachable but the camera is not."
  echo
  echo "That split is the signature of macOS Local Network privacy: outbound"
  echo "connections to the internet are ungated, connections to the LAN are not."
  echo "It is also what a powered-off camera or a wrong CAMERA_IP looks like,"
  echo "so confirm by running this same script directly in a GUI Terminal:"
  echo "  - works in Terminal, fails as agent -> permission problem"
  echo "  - fails both ways                   -> camera or network problem"
elif [[ "$internet" == fail ]]; then
  echo "No internet either, so this is a plain network outage, not permissions."
  echo "The club's router does this overnight; run.sh retries every 5 minutes."
elif [[ "$lan" == ok ]]; then
  echo "TCP to port 554 succeeds but RTSP does not open, so the network path and"
  echo "any Local Network permission are fine. Look at credentials or the URL:"
  echo "$probe_out" | sed 's/^/  /'
fi
