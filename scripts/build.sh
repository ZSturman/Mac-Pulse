#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
CONFIGURATION="${CONFIGURATION:-Debug}"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required. Open Xcode once to finish setup, then retry." >&2
  exit 1
fi
if [[ ! -d MacPulse.xcodeproj ]]; then
  if ! command -v xcodegen >/dev/null; then
    echo "Missing generated project. Install XcodeGen or restore MacPulse.xcodeproj." >&2
    exit 1
  fi
  xcodegen generate
fi
xcodebuild -project MacPulse.xcodeproj -scheme MacPulse -configuration "$CONFIGURATION" \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath build/DerivedData-mac \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build "$@"
echo "Built: $PROJECT_DIR/build/DerivedData-mac/Build/Products/$CONFIGURATION/Mac Pulse.app"
