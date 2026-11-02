# WacomViewportLock

[![CI](https://github.com/badoriie/WacomViewportLock/actions/workflows/ci.yml/badge.svg)](https://github.com/badoriie/WacomViewportLock/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/badoriie/WacomViewportLock?include_prereleases)](https://github.com/badoriie/WacomViewportLock/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A macOS 14+ menu-bar utility that shows a floating, semi-transparent rectangle with the same aspect ratio as your Wacom tablet's active area. Lock it, and the overlay becomes click-through while your pen input is remapped to stay inside the rectangle. Your handwriting in the app underneath then matches the size of your physical hand movements.

## Install

Download the latest `.dmg` from [Releases](https://github.com/badoriie/WacomViewportLock/releases) and drag the app to Applications. Releases aren't notarized yet, so the first time, right-click the app › **Open** › **Open**. Then grant Accessibility access when asked.

## Build & run

```sh
./build_app.sh
open build/WacomViewportLock.app
```

Optional: `SIGN_IDENTITY="Apple Development: …" ./build_app.sh` signs with a real identity. Ad-hoc signed builds can lose their Accessibility grant each time you rebuild.

## Development

```sh
swift build                                                           # compile
swift test                                                            # unit tests
swift format lint --strict -r Sources Tests scripts Package.swift     # style check (CI enforces it)
swift format format --in-place -r Sources Tests scripts Package.swift # auto-fix style
```

CI (`.github/workflows/ci.yml`) runs the lint, build and tests on every push and pull request, and uploads the zipped app bundle as an artifact. The unit tests cover the mapping math, display clamping, physical sizing and settings. Pen behaviour itself needs a real tablet.

## Contributing

`main` is protected: every change goes through a pull request that must pass **Lint**, **Build & test** and **SonarCloud** before it can be squash-merged. Force pushes are blocked. Report security issues privately; see [SECURITY.md](SECURITY.md).

## Releasing

Releases are built by `.github/workflows/release.yml` when a version tag is pushed:

```sh
git tag v1.0.0
git push origin v1.0.0
```

The workflow runs the tests and stamps the version into the app. It then publishes a GitHub Release with a `.dmg`, a `.zip` and `SHA256SUMS.txt`. Tags with a suffix, such as `v1.1.0-beta.1`, are published as pre-releases. Builds are ad-hoc signed; Developer ID signing and notarization can be added later.

## App icon

`Resources/AppIcon.icns` is generated from code. To change it, edit `scripts/make_icon.swift`, then run `swift scripts/make_icon.swift && ./build_app.sh`.

## Usage

| Action | How |
|---|---|
| Move overlay | Click-drag anywhere inside it (unlocked) |
| Resize | Only when 1:1 mode is off: drag the bottom-right grip or any edge; the aspect ratio stays locked |
| Lock / unlock | Menu bar › Lock Viewport, or **⌃⌥⌘L** from anywhere |
| Lock button (top-right of the overlay) | Locks or unlocks the overlay. You can tap it with the pen while the overlay is locked. |
| Tablet size, mapping, color, opacity | Menu bar › Calibration… |
| True 1:1 size | Calibration › "Keep overlay at physical size (1:1)" (on by default) keeps the overlay at the tablet's real size, on every display |
| Exact screen scale | Calibration › Screen Calibration: measure the overlay's width with a ruler and enter it. The correction is saved per monitor. |

## Permissions

Locking requires **Accessibility** access (System Settings › Privacy & Security › Accessibility), because it uses a `CGEventTap` that modifies events. The app is not sandboxed.

## Wacom driver setup

- In Wacom Tablet Properties › Mapping, map the tablet to a single monitor and turn off **Force Proportions**.
- In Calibration › "Tablet mapped to", choose **the same monitor**, and keep the overlay on that monitor.
- Remapping applies only to pen events. Your mouse and trackpad are not affected.
- After you lock the overlay for the first time, unlocking puts the pen in mouse mode until you quit the app. In mouse mode the pen moves the pointer from where it is (relative movement), so unlocking never makes the pointer jump. Lifting the pen and putting it down elsewhere doesn't move the pointer.
- While locked, the system cursor is hidden while the pen is near the tablet, and a small dot inside the overlay marks the pen tip. Hiding the cursor while another app is in front uses an undocumented macOS feature, so the app can't go on the Mac App Store.
- While the overlay is locked, the system cursor follows the remapped pen position.
- To debug pen remapping, run `log stream --level debug --predicate 'subsystem == "com.example.WacomViewportLock"'`. It shows each pen event's original and remapped position.

## Source layout

```
Sources/WacomViewportLock/
  App.swift                    @main entry point
  AppDelegate.swift            wiring, global hotkey, screen-change handling
  AppSettings.swift            @Observable settings model + presets (UserDefaults)
  ViewportController.swift     lock state, mapping rects, 1:1 physical sizing
  OverlayWindowController.swift  floating window + drawing/drag/resize view
  TabletRemapper.swift         CGEventTap + coordinate remapping
  GlobalHotKey.swift           Carbon RegisterEventHotKey wrapper
  ToolbarController.swift      lock button panel in the overlay's top-right corner
  PointerWindow.swift          arrow-pointer stand-in for pen mouse mode
  SystemCursor.swift           hides the system cursor while the pen is remapped
  StatusBarController.swift    NSStatusItem menu + calibration popover
  CalibrationView.swift        SwiftUI settings popover
  ScreenGeometry.swift         display IDs, Cocoa↔CG coordinate conversion
  Permissions.swift            Accessibility checks/prompt
  ObservationSupport.swift     withObservationTracking helper for AppKit

Tests/WacomViewportLockTests/  unit tests (Swift Testing)
scripts/make_icon.swift        renders Resources/AppIcon.icns
```

## License

[MIT](LICENSE)
