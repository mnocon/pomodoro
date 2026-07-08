#!/bin/bash
# Build a standalone PomodoroBar.app bundle from the SwiftPM release build.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/PomodoroBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/PomodoroBar "$APP/Contents/MacOS/PomodoroBar"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.marek.pomodorobar</string>
    <key>CFBundleName</key><string>PomodoroBar</string>
    <key>CFBundleExecutable</key><string>PomodoroBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP — run with: open $APP"
