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

# 2. Plain TCP to the camera's RTSP port, using nc. Note that nc is an
#    Apple-signed system binary and ffmpeg is not, and Local Network
#    permission is granted per binary — so nc succeeding says the camera is
#    up and routable, but says NOTHING about whether ffmpeg is allowed to
#    talk to it. That difference is the whole diagnosis below.
if nc -z -G 4 -w 4 "$CAMERA_IP" 554 2> /dev/null; then
  lan=ok
else
  lan=fail
fi
echo "lan (nc): $lan"

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

# macOS does not report a blocked local-network connection as a permission
# error. It synthesises EHOSTUNREACH / ENETUNREACH instead, so a denied
# ffmpeg looks exactly like a unplugged camera.
blocked_signature='No route to host|Network is unreachable|Host is down'

if [[ $probe_rc -eq 0 ]]; then
  echo "Camera opens fine from this context."
  echo "$probe_out" | sed 's/^/  /'
elif [[ "$lan" == ok ]] && echo "$probe_out" | grep -qE "$blocked_signature"; then
  echo "BLOCKED BY LOCAL NETWORK PRIVACY."
  echo
  echo "nc reached $CAMERA_IP:554, so the camera is up and routable. ffmpeg,"
  echo "from this same context, was told 'no route to host'. Both cannot be"
  echo "true of the network — so this is macOS denying ffmpeg specifically."
  echo "nc is an Apple-signed system binary; Homebrew ffmpeg is not, and the"
  echo "permission is granted per binary."
  echo
  echo "Fix: System Settings > Privacy & Security > Local Network, enable the"
  echo "entry for ffmpeg (it appears only after a denial like this one), then"
  echo "  launchctl kickstart -k gui/\$(id -u)/com.brookcam.stream"
  echo "If no entry appears, use the Terminal route — see SETUP.md."
  echo
  echo "$probe_out" | sed 's/^/  /'
elif [[ "$internet" == ok && "$lan" == fail ]]; then
  echo "The internet is reachable but the camera is not, and nc cannot reach it"
  echo "either. Most likely the camera is powered off, or CAMERA_IP is wrong."
  echo "Confirm by running this same script directly in a GUI Terminal:"
  echo "  - works in Terminal, fails as agent -> permission problem after all"
  echo "  - fails both ways                   -> camera or network problem"
elif [[ "$internet" == fail ]]; then
  echo "No internet either, so this is a plain network outage, not permissions."
  echo "The club's router does this overnight; run.sh retries every 5 minutes."
else
  echo "TCP to port 554 succeeds and the failure does not look like a privacy"
  echo "block. Check credentials or the stream path:"
  echo "$probe_out" | sed 's/^/  /'
fi
