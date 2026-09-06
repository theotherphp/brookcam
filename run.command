#!/bin/bash
# Double-clickable wrapper that runs run.sh inside Terminal.app.
#
# This is the fallback for the launchd agents (see install-launchd.sh): add
# this file to System Settings > General > Login Items, and macOS opens it in
# Terminal.app at login. That matters because Local Network permission is
# granted to the *responsible* app — under Terminal.app, ffmpeg inherits the
# grant that already works when you start the stream by hand.
cd "$(dirname "$0")" && exec ./run.sh
