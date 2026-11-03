# WacomViewportLock

macOS 14+ menu-bar app (Swift 5 language mode, SwiftPM, AppKit + SwiftUI). It shows a floating overlay with the same aspect ratio and physical size as the user's Wacom tablet. When locked, pen input is remapped 1:1 into the overlay via `CGEventTap`.

## Build & run

- `swift build`: compile check.
- `swift test`: unit tests (Swift Testing) for the pure logic: overlay mapping, display clamping, physical-size frame, settings persistence.
- `swift format lint --strict -r Sources Tests scripts Package.swift`: the pre-commit hook and the release fail on any warning. Fix with `swift format format --in-place …`. Config lives in `.swift-format`.
- `./build_app.sh`: release build, wrapped and ad-hoc signed as `build/WacomViewportLock.app`.
- Relaunch with the `relaunch` skill (`.claude/skills/relaunch`). `open` on a running app only re-activates the **old** instance, so quit it first and verify the new process start time.
- App icon: `swift scripts/make_icon.swift` regenerates `Resources/AppIcon.icns` (nib-lock artwork). `build_app.sh` copies it into the bundle.
- Pen debugging: `log stream --level debug --predicate 'subsystem == "com.example.WacomViewportLock"'` logs every pen event's original and rewritten location.

Lint, build and tests run in the pre-commit hook (`.pre-commit-config.yaml`; enable once with `pre-commit install`). It needs Xcode: the Command Line Tools lack SwiftUI's macro plugin. There is no CI on pushes or PRs, so never skip the hook. When adding logic, keep the math in pure (often `static`) functions and add tests. Pen behaviour itself can only be verified by the user on a real tablet, so say so plainly instead of claiming it works. Screenshots need Screen Recording permission, which the shell doesn't have. To check layout, list window frames with the `relaunch` skill's `list_windows.swift`.

Rebuilding with ad-hoc signing can invalidate the Accessibility grant. If locking fails, tell the user to re-add the app in System Settings › Privacy & Security › Accessibility.

## Architecture

| File | Role |
|---|---|
| `ViewportController` | Owns overlay, remapper, lock button, pointer window. Lock state, mapping rects, 1:1 sizing, screen calibration. |
| `TabletRemapper` | Two event taps (HID + session). Mappings `.overlay` (locked) and `.relative` (mouse mode). |
| `OverlayWindowController` | `OverlayWindow` + `OverlayView` (fill, border, grip, hint, pen-tip dot layer). |
| `ToolbarController` | Non-activating panel with only the lock button, top-right inside the overlay, attached as a child window. |
| `PointerWindow` | Arrow-pointer stand-in at cursor window level, used in mouse mode. |
| `SystemCursor` | Hides the system cursor while another app is frontmost (private CGS property). Re-hides on app activation. |
| `AppSettings` | `@Observable` model persisted to `UserDefaults`. `observeContinuously` bridges it to AppKit. |
| `UpdaterController` | Sparkle auto-updates and the "Check for Updates…" menu item. Disabled for unbundled runs. |
| `ScreenGeometry` | Display IDs, AppKit (bottom-left origin) ↔ CG (top-left origin) conversion. Always convert through it. |

## Invariants: read before touching remapping or cursor code

Each of these fixed a bug the user hit. Use the `remap-reviewer` agent on any change to `TabletRemapper`, `SystemCursor`, `PointerWindow` or `ViewportController`.

1. **Every pen event must carry the rewritten location**, including button events, which reuse `lastMappedPoint`. Even one un-rewritten event draws stray lines that radiate from the mapping's fixed point.
2. **Rewrite at the HID tap and tag with `eventSourceUserData`.** The session tap only handles untagged events. Never warp the cursor on every event: warp in `syncCursor` only when it's out of place, otherwise it flickers.
3. **The window server draws the cursor at the pen's original position before any tap runs.** That's why the system cursor is hidden while the pen is active, with stand-ins: a 3 pt dot in the overlay when locked, the arrow `PointerWindow` in mouse mode.
4. **App activation changes un-hide the cursor silently.** `SystemCursor` re-asserts on `didActivateApplication` and checks visibility via `CGCursorIsVisible` (loaded with `dlsym`).
5. **Lock and unlock take effect immediately.** After the first lock, unlocking switches to mouse mode (relative movement) until the app quits, so the pointer never jumps. The user rejected deferring changes until the pen leaves or enters range; don't reintroduce it.
6. **The mapping target is the full overlay window frame.** The border is drawn on its outer edge, so aspect ratio and physical size stay exact.
7. **Mouse mode clamps to the nearest real display**, not the bounding box of all displays.

## Product decisions (don't undo without being asked)

- **Tablet → monitor mapping is chosen manually** in Calibration, with a warning that it must match the Wacom settings. Automatic detection (reading the Wacom prefs file or inferring from pen movement) was tried and removed at the user's request.
- **Toolbar:** only the lock button, top-right inside the overlay. Pen/eraser and undo/redo were removed, and so was the lock badge at the top-left.
- **Opacity** applies to the fill only. The border stays opaque. Minimum opacity is 0.05, because fully transparent pixels let clicks fall through.
- **1:1 physical-size mode** is on by default. Screen scale can be corrected per monitor with a ruler measurement.

## Conventions

- `@MainActor` for UI and controllers. The event-tap callbacks run on the main run loop.
- Comments explain *why*, especially for macOS quirks. Match the existing style and density.
- Private or undocumented APIs (`CGSSetConnectionProperty`, `CGCursorIsVisible` via `dlsym`) are acceptable here: this is a personal tool, not for the App Store. Keep them isolated in `SystemCursor`.

## CI & releases

- **No CI on pushes or PRs** (the user's choice: macOS runners were too slow to start). The pre-commit hook does the checking, and the release re-runs everything.
- **Versions and changelog are automatic (release-please).** PR titles must be Conventional Commits, because squash merges make the title the commit on `main`. `fix:` bumps the patch version. `feat:` and breaking changes (`feat!:`) bump the minor version while below 1.0. `build:` is listed in the changelog without forcing a bump on its own. `docs:`, `ci:`, `chore:`, `refactor:`, `test:` and `style:` are hidden. A `Release-As: X.Y.Z` line in the PR body forces a version.
- `.github/workflows/release.yml`, on every push to `main`: release-please updates the open release PR (version in `.release-please-manifest.json`, `CHANGELOG.md`). **Merging the release PR is the release.** It creates a draft release and its tag. The build job then lints, tests, builds (`VERSION` and `BUILD_NUMBER` stamped in by `build_app.sh`), verifies the signature, attaches the DMG, zip, SHA-256 sums and appcast, and only then publishes the draft. A failed build leaves a draft and a tag. Fix forward with a new version, because tags can't be moved. Builds are ad-hoc signed and not notarized (a deliberate choice for now). There's no automatic path for pre-releases.
- **Auto-updates (Sparkle):** `SUFeedURL` points at `releases/latest/download/appcast.xml`, so pre-releases are never offered. The release workflow signs the zip with the `SPARKLE_ED_PRIVATE_KEY` secret and attaches a one-item `appcast.xml`. It fails without the secret. The matching `SUPublicEDKey` is in `Info.plist`, and the private key is in the owner's login Keychain (account `WacomViewportLock`). Never regenerate it: installed copies would reject every future update. `sparkle:version` is the release run number, so it only goes up.
- Dependabot keeps the action versions current. License: MIT.
- Merging the release PR publishes a release, so only merge it when the user asks. Never push `v*` tags by hand.
- **SonarCloud** analyses every push automatically (GitHub app, project `badoriie_WacomViewportLock`, no config in the repo). **After every push, run the `check-quality` skill** and fix every open SonarCloud issue or hotspot, then push again until the quality gate is `OK`. The user asked for this to happen every time.
- Pin GitHub Actions to full commit SHAs with a `# vX.Y.Z` comment; SonarCloud flags version tags as a security issue.
- Always run SwiftPM with `--only-use-versions-from-resolved-file` in workflows and scripts; SonarCloud flags unlocked dependency resolution as a security issue.
- For unused parameters in overrides, delegate methods and C callbacks, keep the label and drop the internal name (`with _: NSEvent`); SonarCloud flags them otherwise.

## Git

- Public repo `badoriie/WacomViewportLock`. Commit email for this repo is `amir@nasari.me`, set in local git config.
- Commit or push only when asked. **Use the `git-workflow` agent** (`.claude/agents/git-workflow.md`) for all git work: a branch per change, then a pull request with **auto-merge on by default** (squash), so it merges once the checks pass. Release-please release PRs never get auto-merge: merging one publishes a release, so only when the user asks.
- `main` is protected by the **Protect main** ruleset, with no bypass, even for the owner. It requires a pull request and squash merges only. Only `SonarCloud Code Analysis` must pass, on a branch that's up to date, and review threads must be resolved. Force pushes and deletion are blocked. Direct pushes to `main` are rejected (GH013).
- The **Protect release tags** ruleset stops `v*` tags from being moved or deleted; a bad release gets a new patch version.
- Never force-push or rewrite pushed history, even on feature branches. Update a branch by merging `origin/main` into it.
- Repo settings: squash-only merges (PR title/body), auto-merge allowed, head branches deleted after merge, Dependabot alerts and security updates on, secret scanning with push protection on, private vulnerability reporting on, and Actions tokens read-only by default.
