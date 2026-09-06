#!/bin/bash
# Double-clickable wrapper that runs watchdog.sh inside Terminal.app.
# See run.command for why this exists.
cd "$(dirname "$0")" && exec ./watchdog.sh
