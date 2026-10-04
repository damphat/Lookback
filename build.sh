#!/bin/bash
# Build Lookback.app into ./dist
set -e
cd "$(dirname "$0")"
swift build -c release
APP=dist/Lookback.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Lookback.icns "$APP/Contents/Resources/Lookback.icns"
cp .build/release/Lookback "$APP/Contents/MacOS/Lookback"
echo "OK: $APP"
echo "Chạy: open $APP"
echo "Lần đầu mở: vào System Settings > Privacy & Security > Screen Recording, tick Lookback."
