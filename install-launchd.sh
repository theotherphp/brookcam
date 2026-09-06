#!/bin/bash
# Install (or remove) the launchd agents that keep brookcam running across
# reboots of the Mac mini.
#
# Run this ON THE MAC MINI, as the user that owns the camera setup (gm).
# Do NOT run it with sudo — these are per-user LaunchAgents, and a root
# LaunchDaemon is exactly the configuration that failed in March: root has
# no GUI session, so it gets neither Local Network permission nor
# VideoToolbox, and its $HOME is not /Users/gm so brookcam.env is not found.
#
#   ./install-launchd.sh            install and start
#   ./install-launchd.sh uninstall  stop and remove
#
# See "Surviving a reboot" in SETUP.md for the auto-login and Local Network
# steps that have to be done once by hand.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"
DOMAIN="gui/$(id -u)"
LABELS=(com.brookcam.stream com.brookcam.watchdog)

if [[ $EUID -eq 0 ]]; then
  echo "Do not run this with sudo — these are per-user agents." >&2
  exit 1
fi

# Homebrew tools (ffmpeg, ts, jq, yt-dlp) are not on launchd's default PATH.
if command -v brew > /dev/null 2>&1; then
  BREW_BIN="$(brew --prefix)/bin"
else
  BREW_BIN="/opt/homebrew/bin"
fi
AGENT_PATH="$BREW_BIN:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

unload_all() {
  for label in "${LABELS[@]}"; do
    launchctl bootout "$DOMAIN/$label" 2> /dev/null || true
  done
}

if [[ "${1:-}" == "uninstall" ]]; then
  unload_all
  for label in "${LABELS[@]}"; do rm -f "$AGENT_DIR/$label.plist"; done
  echo "Removed brookcam launchd agents. Start the scripts by hand as before."
  exit 0
fi

for tool in ffmpeg ts jq yt-dlp; do
  command -v "$tool" > /dev/null 2>&1 || echo "WARNING: $tool not found in PATH"
done

mkdir -p "$AGENT_DIR" "$LOG_DIR"

write_agent() {
  local label="$1" script="$2" log="$3"
  cat > "$AGENT_DIR/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$label</string>

	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$SCRIPT_DIR/$script</string>
	</array>

	<key>WorkingDirectory</key>
	<string>$SCRIPT_DIR</string>

	<key>EnvironmentVariables</key>
	<dict>
		<key>PATH</key>
		<string>$AGENT_PATH</string>
	</dict>

	<!-- Start at login (auto-login makes that "at boot") and restart the
	     script if it ever exits. run.sh and watchdog.sh loop forever, so
	     this only fires if something kills them outright. -->
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>30</integer>

	<!-- Aqua only: ffmpeg needs a GUI session for VideoToolbox hardware
	     encoding and for Local Network access to the camera. -->
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>ProcessType</key>
	<string>Interactive</string>

	<key>StandardOutPath</key>
	<string>$LOG_DIR/$log</string>
	<key>StandardErrorPath</key>
	<string>$LOG_DIR/$log</string>
</dict>
</plist>
PLIST
}

write_agent com.brookcam.stream   run.sh      brookcam.log
write_agent com.brookcam.watchdog watchdog.sh brookcam-watchdog.log

unload_all
for label in "${LABELS[@]}"; do
  launchctl bootstrap "$DOMAIN" "$AGENT_DIR/$label.plist"
done

echo "Installed and started:"
for label in "${LABELS[@]}"; do
  echo "  $label"
done
cat <<NEXT

Logs:
  tail -f ~/Library/Logs/brookcam.log
  tail -f ~/Library/Logs/brookcam-watchdog.log

Status:
  launchctl list | grep brookcam

If ffmpeg reports the camera as unreachable, that is macOS Local Network
privacy, not launchd. Open System Settings > Privacy & Security >
Local Network, enable the entry for ffmpeg (or bash), then:

  launchctl kickstart -k gui/$(id -u)/com.brookcam.stream

See "Surviving a reboot" in SETUP.md for the full checklist.
NEXT
