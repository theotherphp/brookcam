#!/bin/bash
# Deploy brookcam LaunchAgents on the Mac mini
# Run this once after git pull to install and start the agents

set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
STREAM_PLIST="com.brookcam.stream.plist"
WATCHDOG_PLIST="com.brookcam.watchdog.plist"

echo "Deploying brookcam from $REPO_DIR"

# Pull latest
git -C "$REPO_DIR" pull

# Unload existing agents (ignore errors if not loaded)
launchctl unload "$LAUNCH_AGENTS_DIR/$STREAM_PLIST" 2>/dev/null || true
launchctl unload "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST" 2>/dev/null || true

# Kill any running ffmpeg from previous brookcam runs
pkill -x ffmpeg 2>/dev/null || true

# Copy plists into place
cp "$LAUNCH_AGENTS_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/$STREAM_PLIST.bak" 2>/dev/null || true
cp "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST" "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST.bak" 2>/dev/null || true
cp "$REPO_DIR/$STREAM_PLIST" "$LAUNCH_AGENTS_DIR/"
cp "$REPO_DIR/$WATCHDOG_PLIST" "$LAUNCH_AGENTS_DIR/"

# Load agents
launchctl load "$LAUNCH_AGENTS_DIR/$STREAM_PLIST"
launchctl load "$LAUNCH_AGENTS_DIR/$WATCHDOG_PLIST"

echo "Agents loaded. Starting stream now..."
launchctl start com.brookcam.stream

echo ""
echo "Done. Check status with:"
echo "  tail -f /tmp/brookcam.log"
echo "  tail -f /tmp/brookcam-watchdog.log"
