#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
mkdir -p build
PROBE_APP="$PROJECT_DIR/build/WidgetSandboxProbe.app"
mkdir -p "$PROBE_APP/Contents/MacOS"
cat > "$PROBE_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.local.MacPulse.WidgetSandboxProbe</string>
<key>CFBundleExecutable</key><string>WidgetSandboxProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
xcrun swiftc MacPulse/Core/Metrics.swift MacPulse/Core/SystemSampler.swift \
  Tests/WidgetProbe/main.swift -o "$PROBE_APP/Contents/MacOS/WidgetSandboxProbe"
codesign --force --sign - --entitlements MacPulse/Widget/MacPulseWidget.entitlements \
  "$PROBE_APP"
"$PROBE_APP/Contents/MacOS/WidgetSandboxProbe"
