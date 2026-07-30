#!/bin/bash

# @raycast.schemaVersion 1
# @raycast.title Restart Nowsee
# @raycast.mode compact
# @raycast.icon 🌈
# @raycast.packageName Nowsee
# @raycast.description Quit and relaunch the Nowsee audio visualizer

APP="/Applications/Nowsee.app"

if [ ! -d "$APP" ]; then
    echo "Nowsee is not installed in /Applications — run 'make install'"
    exit 1
fi

pkill -INT -f "Nowsee.app/Contents/MacOS/Nowsee" 2>/dev/null

for _ in $(seq 1 20); do
    pgrep -f "Nowsee.app/Contents/MacOS/Nowsee" >/dev/null || break
    sleep 0.1
done

pkill -KILL -f "Nowsee.app/Contents/MacOS/Nowsee" 2>/dev/null

open "$APP"
echo "Nowsee restarted"
