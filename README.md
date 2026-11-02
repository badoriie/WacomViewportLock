# WacomViewportLock

A macOS 14+ menu-bar utility that shows a floating, semi-transparent rectangle with the same aspect ratio as your Wacom tablet's active area. Lock it, and the overlay becomes click-through while your pen input is remapped to stay inside the rectangle. Your handwriting in the app underneath then matches the size of your physical hand movements.

## Build & run

```sh
./build_app.sh
open build/WacomViewportLock.app
```

Optional: `SIGN_IDENTITY="Apple Development: …" ./build_app.sh` signs with a real identity. Ad-hoc signed builds can lose their Accessibility grant each time you rebuild.

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
  StatusBarController.swift    NSStatusItem menu + calibration popover
  CalibrationView.swift        SwiftUI settings popover
  ScreenGeometry.swift         display IDs, Cocoa↔CG coordinate conversion
  Permissions.swift            Accessibility checks/prompt
  ObservationSupport.swift     withObservationTracking helper for AppKit
```
