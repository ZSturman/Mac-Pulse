# Mac Pulse

A native macOS app that helps you understand what your CPU and memory are doing, with a live dashboard, menu bar monitor, and desktop widget.

Built with SwiftUI, Swift Charts, and WidgetKit. No Python installation, accounts, third-party runtime dependencies, or network service required.

## Features

- Live CPU activity across all logical cores, user/system breakdown, and headroom.
- Memory usage and pressure, with app, wired, and compressed RAM explained.
- Five-minute charts of actual readings collected while the app runs.
- Processes searchable by process name, app name, or PID, sortable by CPU or resident memory.
- Fading highlights for processes that climb into or within the top five.
- Swap, home-volume storage, uptime, and thermal state for context.
- Alerts for sustained high CPU, memory pressure, thermal pressure, and low storage: a notification plus a menu bar item that appears only while something needs attention.
- Optional always-on menu bar readout and open-at-login.
- Small, medium, and large desktop widgets showing their sample time.
- Settings for 1-, 2-, or 5-second app updates, pause/resume, and a built-in guide.

The summary prioritizes memory pressure over RAM percentage: macOS using most of your RAM does not, by itself, indicate a problem.

## Quick start

Requires **macOS 14 Sonoma or later** and **full Xcode 15 or later**. Open Xcode once to complete setup. Compiled on macOS 27.2.1 with Xcode 27.2 on Apple silicon; older supported versions and Intel still need device validation.

From this folder:

```sh
./scripts/run.sh
```

This builds the app and embedded widget, signs them locally, installs **Mac Pulse.app** in `~/Applications`, registers the widget extension, and opens the dashboard. No Apple Developer account is needed for this local build. Quit an earlier running copy with **Command-Q** before rerunning.

To open it later, use Finder → your home folder → Applications, or:

```sh
open "$HOME/Applications/Mac Pulse.app"
```

## Add the widget

1. Run Mac Pulse at least once.
2. Right-click the desktop → **Edit Widgets**, or open Notification Center → Edit Widgets.
3. Search for **Mac Pulse**.
4. Drag a small, medium, or large widget onto the desktop or into Notification Center.
5. Click the widget to open the live dashboard.

**Widgets are snapshots.** Each independently measures this Mac when WidgetKit requests an update, including when the app is quit. It requests its next update after 15 minutes; macOS may defer it. The sample time is visible. The app's interval does not affect widgets. See Apple's [widget refresh guidance](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

The extension is compiled, embedded, signed, and registered. Its sampling APIs also passed a separate signed App Sandbox probe. Placement, readings, and visual fit inside the actual desktop widget host still require a manual check.

## Usage

**Overview** explains current activity and shows rolling CPU/memory charts. The chart starts empty and fills with observed readings. The first CPU reading needs two samples. A dash indicates an unavailable reading or a needed baseline.

**Processes** lists accessible individual processes, including helpers. Switch CPU/Memory sorting to find the largest consumers. Search filters the rows while keeping their rank in the full list. In Processes and Overview, a mint highlight and an upward arrow show when a process climbs into or within the top five between live samples.

Select a row to see its app, parent process, PID, and executable path when available. App attribution uses the executable’s app bundle first, then walks the live parent process chain for helpers outside the bundle. A process can be unattributed if it has no identifiable app bundle or its original parent has exited. The app is read-only and does not terminate processes.

**How to read your Mac** explains the metrics and widget setup. **Settings** changes the requested app interval, menu bar visibility, alerts, and open-at-login; choices persist locally.

**Alerts.** While Mac Pulse is open (window closed is fine), it watches for:

| Alert | Raised when | Clears when |
| --- | --- | --- |
| CPU | Overall CPU averages at least 85% over a minute (75% or 95% in Settings) | The one-minute average falls 10 points below the threshold |
| Memory | macOS memory pressure is Elevated for 30 seconds, or High (immediately) | Pressure is Normal for 30 seconds |
| Heat | macOS thermal state is Serious or Critical | It stays below Serious for 30 seconds |
| Storage | Less than 10 GB free on the home volume (critical below 2 GB) | At least 15 GB is free |

Each new alert posts one notification. A kind does not notify again for 30 minutes unless it becomes critical. Click the notification to open the dashboard (Processes for CPU, memory, and heat). By default the menu bar item appears only while an alert is active. It shows the most important alert (for example `CPU 93%`), and its panel explains each alert, lists the top three processes, and links to the dashboard. While a CPU, memory, or heat alert is active, Mac Pulse samples processes even with the window closed so it can show what is responsible. macOS exposes a thermal *category*, not temperatures or per-app energy, so "heat" means macOS-reported thermal pressure. macOS asks for notification permission on first launch.

Close the window to keep monitoring. Open it again from the Dock, from an alert, or from the menu bar (if set to Always). While the dashboard window is closed, minimized, or covered, Mac Pulse skips process enumeration and stops redrawing, so its own CPU use stays low; graph history keeps recording. Quit with **Command-Q** to stop app sampling. Turn on **Settings → Open at login** to monitor all the time; macOS may ask you to approve it under General → Login Items.

| Action | Shortcut |
| --- | --- |
| Pause/resume | Command-Shift-P |
| Settings | Command-comma |
| Quit | Command-Q |

## How the readings work

| Reading | Source and interpretation |
| --- | --- |
| Overall CPU | Deltas of Mach `HOST_CPU_LOAD_INFO` counters; all logical cores combined range from 0–100%. |
| Process CPU | `proc_pidinfo` task CPU deltas, converted from Mach ticks with the native timebase, divided by monotonic elapsed time. 100% means one logical core, so a process can exceed 100%. Start times detect reused PIDs. |
| Memory used | Anonymous/internal pages minus purgeable pages, plus wired and compressor pages, multiplied by the kernel page size. Reclaimable file cache is excluded. |
| Memory pressure | macOS `kern.memorystatus_vm_pressure_level`. Unavailable if the OS denies or does not provide it. |
| Process memory | Resident RAM, potentially including shared pages. Different from Activity Monitor's physical-footprint column; rows should not be summed to match system memory. |
| Swap | `vm.swapusage`; allocated swap may remain after pressure subsides. |
| Storage | Free space on the home volume; Finder may additionally count purgeable space. |
| Thermal state / uptime | `ProcessInfo`; thermal state is a category, not a temperature sensor. |

Readings may differ from Activity Monitor due to sampling times, rounding, and definitions. Protected or exited processes are omitted and counted. Kernel-provided process names can be shortened. System CPU includes work from processes the app cannot inspect.

The process CPU timebase follows Apple's [task accounting implementation](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c). The app uses platform APIs, with no shell polling or privileged helper.

## Architecture and privacy

`MacPulse/App` owns the SwiftUI window, menu bar, settings, and serial background sampling queue. The main thread publishes readings and renders views. CPU baselines restart after pause, interval changes, or wake. Chart history is limited to five minutes and 301 points, held in memory, and cleared on quit.

`MacPulse/Core` contains shared calculations and sampling, compiled into both targets. `MacPulse/Widget` independently samples aggregate statistics and provides one real timeline entry. This avoids shared files, App Groups, a running helper, and developer-account setup for local use.

The app is unsandboxed to inspect accessible processes; the widget is sandboxed. Neither uses network access, root privileges, Accessibility access, Full Disk Access, or stored process logs. WidgetKit manages its rendered snapshots separately.

## Development

The generated project is included. Open `MacPulse.xcodeproj` and select the **MacPulse** scheme, or:

```sh
# Build app + embedded widget without installing or launching.
./scripts/build.sh

# Metric checks and bounded, read-only live sampling checks.
./scripts/test.sh

# Check aggregate APIs with the widget's App Sandbox entitlement.
./scripts/test-widget-sandbox.sh
```

Expected: `BUILD SUCCEEDED`, `PASS: 52 core checks`, and a sandbox probe `PASS`. The CPU check performs about 0.2 seconds of bounded work in the test process and compares with `getrusage`. The sandbox probe uses a temporary signed test app under `build/`. Neither controls other processes or replaces UI/widget-host validation.

Builds reuse `build/DerivedData-mac`. App output: `build/DerivedData-mac/Build/Products/Debug/Mac Pulse.app` (`CONFIGURATION=Release ./scripts/build.sh` builds the optimized copy that `run.sh` installs). Test output: `build/CoreChecks`. Both are ignored by Git.

`project.yml` is the configuration source. After changing target membership, build settings, or generated Info.plist values, regenerate with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

XcodeGen is only needed to regenerate the included project. Keep the configuration, generated plists/entitlements, and project together. Regenerate the code-drawn icon with:

```sh
swift scripts/make-icon.swift
```

For distribution, choose your own bundle identifiers and signing team for **both** targets, use Developer ID signing, and notarize. Public distribution and App Store submission have not been configured or validated.

## Troubleshooting

| Symptom | Next step |
| --- | --- |
| Xcode tools error | Confirm full Xcode is selected with `xcode-select -p` and complete its setup. If needed: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. |
| App already running during install | Quit with Command-Q, then rerun `./scripts/run.sh`. |
| Widget missing | Open the installed copy, reopen Edit Widgets, and search again. Check `pluginkit -m -v -i com.local.MacPulse.Widget`. If necessary: `pluginkit -a "$HOME/Applications/Mac Pulse.app/Contents/PlugIns/MacPulseWidget.appex"`. If the host rejects ad hoc widget hosting, select your development team and sign both targets in Xcode. |
| Stale widget | Check its sample time. macOS controls refresh; click it for the live app. |
| Missing process or CPU dash | Wait for the next sample. New processes need a baseline; macOS restricts some processes. |
| High RAM percentage | Check pressure and responsiveness together. Normal pressure with high RAM use is expected. |

## Screenshots and validation

The native dashboard, process search, pause/resume, and Settings were checked through the app UI. Computer-use access timed out before a reliable final screenshot and desktop-widget capture. Capture instructions are in [docs/images/README.md](docs/images/README.md); no mock screenshot is presented as the product.

Current evidence and remaining checks: [docs/NEXT_STEPS.md](docs/NEXT_STEPS.md).

## Original prototype

`main.py` and its pinned `psutil` requirement are preserved as historical reference. The native app is the primary startup path. Run the separate terminal prototype with:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python main.py
```

It prints CPU/memory bars until Control-C and is not used by Mac Pulse.

Older audit records remain in [docs/WORKSPACE_RECONCILIATION.md](docs/WORKSPACE_RECONCILIATION.md) and its JSON companion. They describe the Python-only state; this README and current next steps describe the native app.
