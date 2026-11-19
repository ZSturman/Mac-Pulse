# Mac Pulse — CPU and Memory Monitor

## Purpose and boundaries
Native macOS CPU/memory monitor with a SwiftUI dashboard, menu bar panel, and WidgetKit extension. Preserve the original Python prototype (`main.py`, `requirements.txt`) and historical workspace records.

## Map
- `MacPulse/App/`: app, dashboard, processes, settings, menu bar.
- `MacPulse/Core/`: platform sampling and shared display models. Compiled into both targets; no network or shared container.
- `MacPulse/Widget/`: independently sampled WidgetKit snapshots; refresh timing belongs to macOS.
- `project.yml` / `MacPulse.xcodeproj`: XcodeGen source and generated project (keep both current).
- `scripts/`: build, run/install, isolated core checks.
- `Tests/`: deterministic metric math and live read-only sampling checks.
- `README.md`, `docs/NEXT_STEPS.md`, `docs/images/`: setup, continuation, actual screenshots.

## Commands and practices
- `./scripts/run.sh`: build, install in `~/Applications`, open.
- `./scripts/build.sh`: affected macOS app + embedded widget build, stable `build/DerivedData-mac`.
- `./scripts/test.sh`: Swift core checks without UI or user-data changes.
- `./scripts/test-widget-sandbox.sh`: signed test app checks aggregate API access using the widget's App Sandbox entitlement; does not validate WidgetKit hosting.
- `xcodegen generate`: regenerate after project.yml changes (XcodeGen is development-only).
- Prefer native frameworks and no third-party runtime dependencies. Deployment target: macOS 14.
- Keep sampling off the main thread, use monotonic elapsed time for process CPU, bound history, and treat inaccessible processes/failed metrics explicitly.
- Never imply that a WidgetKit snapshot updates continuously. Do not fabricate future readings.
- Preserve read-only operation: no process termination, cleanup, system changes, or remote telemetry. Keep secrets and local readings out of source control.
- Use cheapest useful checks; one stable DerivedData folder; scratch logs in `/tmp`.
- Document signing and widget registration limitations. Delegate visual checks if reliable app capture is unavailable; do not fabricate screenshots.
