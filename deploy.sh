#!/bin/bash
# Deploy brookcam LaunchDaemons on the Mac mini
# Run this once after git pull to install and start the daemons
# Requires sudo (daemons install to /Library/LaunchDaemons)

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_DAEMONS_DIR="/Library/LaunchDaemons"
STREAM_PLIST="com.brookcam.stream.plist"
WATCHDOG_PLIST="com.brookcam.watchdog.plist"

# Ensure we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "LaunchDaemons require root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

echo "Deploying brookcam from $REPO_DIR"

# Pull latest (as the owning user, not root)
sudo -u gm git -C "$REPO_DIR" pull

# Remove existing daemons (ignore errors if not loaded)
launchctl bootout system/"com.brookcam.stream" 2>/dev/null || true
launchctl bootout system/"com.brookcam.watchdog" 2>/dev/null || true

# Kill any running ffmpeg from previous brookcam runs
pkill -x ffmpeg 2>/dev/null || true

# Copy plists into place
cp "$LAUNCH_DAEMONS_DIR/$STREAM_PLIST" "$LAUNCH_DAEMONS_DIR/$STREAM_PLIST.bak" 2>/dev/null || true
cp "$LAUNCH_DAEMONS_DIR/$WATCHDOG_PLIST" "$LAUNCH_DAEMONS_DIR/$WATCHDOG_PLIST.bak" 2>/dev/null || true
cp "$REPO_DIR/$STREAM_PLIST" "$LAUNCH_DAEMONS_DIR/"
cp "$REPO_DIR/$WATCHDOG_PLIST" "$LAUNCH_DAEMONS_DIR/"

# LaunchDaemons must be owned by root:wheel with mode 644
chown root:wheel "$LAUNCH_DAEMONS_DIR/$STREAM_PLIST" "$LAUNCH_DAEMONS_DIR/$WATCHDOG_PLIST"
chmod 644 "$LAUNCH_DAEMONS_DIR/$STREAM_PLIST" "$LAUNCH_DAEMONS_DIR/$WATCHDOG_PLIST"

# Load daemons
launchctl bootstrap system/ "$LAUNCH_DAEMONS_DIR/$STREAM_PLIST"
launchctl bootstrap system/ "$LAUNCH_DAEMONS_DIR/$WATCHDOG_PLIST"

echo "Daemons loaded. Starting stream now..."
launchctl kickstart system/com.brookcam.stream

echo ""
echo "Done. Check status with:"
echo "  tail -f /tmp/brookcam.log"
echo "  tail -f /tmp/brookcam-watchdog.log"
