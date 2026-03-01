#!/bin/bash
# Deploy brookcam LaunchAgents on the Mac mini
# Run this once after git pull to install and start the agents
# Requires sudo (agents install to /Library/LaunchAgents)

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_AGENTS_DIR="/Library/LaunchAgents"
GM_UID=$(id -u gm)
STREAM_PLIST="com.brookcam.stream.plist"
WATCHDOG_PLIST="com.brookcam.watchdog.plist"

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "LaunchAgents require root to install. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

echo "Deploying brookcam from $REPO_DIR"

# Pull latest (as the owning user, not root)
sudo -u gm git -C "$REPO_DIR" pull

# Remove existing agents (ignore errors if not loaded)
launchctl bootout gui/"$GM_UID"/com.brookcam.stream 2>/dev/null || true
launchctl bootout gui/"$GM_UID"/com.brookcam.watchdog 2>/dev/null || true

# Clean up old LaunchDaemons if migrating from system domain
launchctl bootout system/com.brookcam.stream 2>/dev/null || true
launchctl bootout system/com.brookcam.watchdog 2>/dev/null || true
rm -f /Library/LaunchDaemons/com.brookcam.stream.plist /Library/LaunchDaemons/com.brookcam.watchdog.plist

# Kill any running ffmpeg from previous brookcam runs
pkill -x ffmpeg 2>/dev/null || true

# Copy plists into place
cp "$LAUNCH_AGENTS_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/$STREAM_PLIST.bak" 2>/dev/null || true
cp "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST" "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST.bak" 2>/dev/null || true
cp "$REPO_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/"
cp "$REPO_DIR/$WATCHDOG_PLIST" "$LAUNCH_AGENTS_DIR/"

# LaunchAgents must be owned by root:wheel with mode 644
chown root:wheel "$LAUNCH_AGENTS_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST"
chmod 644 "$LAUNCH_AGENTS_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST"

# Load agents into the user's GUI domain
launchctl bootstrap gui/"$GM_UID" "$LAUNCH_AGENTS_DIR/$STREAM_PLIST"
launchctl bootstrap gui/"$GM_UID" "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST"

echo "Agents loaded. Starting stream now..."
launchctl kickstart gui/"$GM_UID"/com.brookcam.stream

echo ""
echo "Done. Check status with:"
echo "  tail -f /tmp/brookcam.log"
echo "  tail -f /tmp/brookcam-watchdog.log"
echo ""
echo "Remember: gm user must have auto-login enabled for boot resilience."
