# Mac Pulse continuation — November 14, 2026

## Current state

Native macOS 14+ SwiftUI app with live dashboard charts, process search/sorting, guidance, settings, menu bar monitoring, and a WidgetKit extension in three sizes. Python prototype and historical workspace records remain unchanged.

Installed local development copy: `~/Applications/Mac Pulse.app`.

## Completed and validated

- Included generated `MacPulse.xcodeproj` and `project.yml`; no runtime dependencies.
- Built app + embedded widget with Xcode 27.2 on macOS 27.2.1, Apple silicon.
- Verified installed signing with `codesign --verify --deep --strict`.
- Confirmed extension registration using `pluginkit -m -v -i com.local.MacPulse.Widget`.
- Passed 25 core checks: CPU rollover/timebase, process CPU versus `getrusage`, VM page math, failure/baseline behavior, summary priorities, and live read-only sampling.
- Passed a separate signed App Sandbox probe using the widget entitlement: aggregate CPU, memory, pressure, and swap APIs are accessible. This is separate from WidgetKit hosting/rendering validation.
- Observed real dashboard/charts, successful process search, pause/resume, and Settings through native UI.
- Fixed segmented control label wrapping found during inspection.
- Documented install/start, architecture, metric definitions, widget expectations, signing, and troubleshooting.

Scratch build log: `/tmp/macpulse-build.log` (disposable). Reusable build output: `build/DerivedData-mac` (ignored). No simulator data or result bundles were created.

## Alerts (November 18, 2026)

Added sustained-condition alerts (`MacPulse/App/Alerts.swift`, deterministic checks in `Tests/main.swift`), local notifications (`AlertNotifier.swift`, logged under subsystem `com.local.MacPulse`, category `alerts`), a menu bar mode (default: only while an alert is active; replaces the old `showMenuBar` toggle), and an open-at-login toggle (`SMAppService`).

Verified on the installed Release build (macOS 27.2.1, Apple silicon):
- 52 core checks, Debug and Release builds, widget sandbox probe `PASS`, `codesign --verify --deep --strict`, widget registration.
- The desktop widget renders live readings in the widget host.
- Notification authorization is granted. A memory-pressure alert posted 30 s after launch and appeared as a banner. A CPU alert posted immediately once a lowered threshold was met by a full minute of samples.
- With no alert active, no menu bar item was inserted; during an alert it was (`NSStatusItem VisibleCC` preference).
- `macpulse://processes` switches the open dashboard to Processes.

Fixed during verification: reused notification identifiers made macOS update the old record silently with no banner; identifiers are now unique per post. `run.sh` merged into the old bundle with `ditto`, leaving stale Debug dylibs that broke the widget's signature seal; it now replaces the bundle.

Unverified (no Accessibility access for UI scripting; menu bar auto-hidden): menu bar item appearance and panel layout, notification click reopening a *closed* dashboard window, and login-item approval for the ad hoc signed build. If the Mac often sits at Elevated pressure, consider notifying for memory only on High.

## Remaining manual checks — developer

Computer-use access timed out while inspecting Notification Center and the final updated window. Widget-gallery hosting and final screenshot/layout checks remain unverified. The app and extension are build-verified.

1. Open the app:

   ```sh
   open "$HOME/Applications/Mac Pulse.app"
   ```

   Expected: changing readings and charts filling from the right. Search Processes for `Mac Pulse`; switch CPU/Memory sorting. Compare plausible process CPU with Activity Monitor, accounting for different intervals and protected processes.

2. Desktop → Edit Widgets → search **Mac Pulse**. Place a medium widget. Expected: actual CPU/memory values and a sample time. Click it to open the live dashboard. Check small/large sizes and light/dark appearances. Quit the app and confirm the widget remains; future updates are scheduled by macOS. Registration alone does not prove these behaviors.

   If missing:

   ```sh
   pluginkit -m -v -i com.local.MacPulse.Widget
   pluginkit -a "$HOME/Applications/Mac Pulse.app/Contents/PlugIns/MacPulseWidget.appex"
   ```

   Reopen Edit Widgets. If registration exists but hosting fails, return the visible error and OS version to Codex. Developer-team signing may be needed; do not weaken system security.

3. Close the window. Expected: with Settings → Show in the menu bar → Always, the CPU item remains and Open Dashboard brings it back; with the default, the item appears only during alerts. Command-Q stops app sampling. Confirm interval/menu bar preferences survive relaunch and the smallest supported window fits.

4. Self-overhead (November 17, 2026): `run.sh` now installs a Release build; rank-rise fades are 0.3 s; the dashboard skips process sampling and redraws while its window is closed, minimized, covered, or on another Space. Measured: Debug build on the Processes page 27–42% CPU; new build with window off screen 2.2% (20 s average). Unverified: visible-window CPU. Open the dashboard in front, confirm readings and process rows update every interval, check Mac Pulse CPU in Activity Monitor on Overview and Processes, then cover the window and confirm it drops.

5. Capture real screenshots following [images/README.md](images/README.md), then embed the dashboard near the top of README.

## Exact next Codex action

Review the widget-host/manual-check result and fix a concrete issue if present. If the gallery works, inspect final dashboard/widget captures, add real images to README, and mark the manual checks complete here. Do not rewrite historical external task records or expand into a backend.

For a code change, use the cheapest relevant check:

```sh
./scripts/test.sh
./scripts/build.sh
./scripts/test-widget-sandbox.sh
```

Expected: 25 passing core checks, `BUILD SUCCEEDED`, then a sandbox probe `PASS`. Quit the running app before `./scripts/run.sh` to replace it.

## Known limitations and priorities

- Release prerequisite: Developer ID signing and notarization are not configured. Local ad hoc build is the delivery path.
- Validation priority: macOS 14 and Intel runtime/builds have not been checked; only this Apple silicon host is verified.
- WidgetKit snapshots are scheduled by macOS. Requested 15-minute refresh is not guaranteed.
- Protected processes can be inaccessible; names can be truncated; resident memory differs from physical footprint and can include shared pages. Storage free excludes Finder's potentially purgeable space.
- Optional, low priority: measure energy impact before optimizing; consider slower process enumeration with all panels hidden while keeping system readings timely. No evidence yet requires this optimization.
- No long-term history, exports, network/disk throughput, temperature sensors, per-app energy, or process control in this version. Alerts run only while the app is open.
