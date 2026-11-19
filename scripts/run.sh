#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# The installed copy runs all day, so build it optimized to keep the monitor's own footprint small.
CONFIGURATION=Release "$PROJECT_DIR/scripts/build.sh"
BUILT_APP="$PROJECT_DIR/build/DerivedData-mac/Build/Products/Release/Mac Pulse.app"
INSTALLED_APP="$HOME/Applications/Mac Pulse.app"
if pgrep -x "Mac Pulse" >/dev/null; then
  echo "Mac Pulse is already running. Quit it with Command-Q, then rerun to install this build." >&2
  exit 1
fi
mkdir -p "$HOME/Applications"
# ditto merges into an existing bundle; stale files (such as old Debug dylibs) would break the signature seal.
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"
# Register the installed extension, so the desktop widget gallery can discover it.
pluginkit -a "$INSTALLED_APP/Contents/PlugIns/MacPulseWidget.appex" || \
  echo "Widget registration was deferred. Launch the app, then reopen Edit Widgets." >&2
open "$INSTALLED_APP"
echo "Opened $INSTALLED_APP"
