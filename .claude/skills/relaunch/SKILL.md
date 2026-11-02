---
name: relaunch
description: Rebuild the WacomViewportLock app bundle and relaunch it so the new build is the one actually running, then verify that and optionally list its window frames. Use after code changes when the user should try the new version, or to check overlay/lock-button layout without screenshots.
---

# Relaunch WacomViewportLock

`open build/WacomViewportLock.app` only re-activates an instance that's already running. It does **not** start the new build. Always quit first, then verify the new process.

## Steps

Run from the repo root.

1. **Build the bundle.** Stop if this reports errors.
   ```sh
   ./build_app.sh 2>&1 | grep -E "error|warning:|Built"
   ```
2. **Quit any running instance.** This may be the user's own session, so mention it in your reply.
   ```sh
   osascript -e 'quit app "WacomViewportLock"'; sleep 1
   pgrep -f WacomViewportLock.app && echo "STILL RUNNING"
   ```
3. **Launch and verify the new build is the one running.** The process start time must come after the binary's modification time.
   ```sh
   open build/WacomViewportLock.app && sleep 3
   ps -o pid,lstart,command -p "$(pgrep -f WacomViewportLock.app)"
   ls -l build/WacomViewportLock.app/Contents/MacOS/WacomViewportLock
   ```
4. **Optional: check window layout.** Screenshots need Screen Recording permission, which the shell doesn't have. Instead, print every on-screen window of the app in CG global coordinates (top-left origin):
   ```sh
   swift .claude/skills/relaunch/list_windows.swift
   ```
   The overlay is the large window. The lock button is a small window about 6 pt inside the overlay's top-right corner. The mouse-mode arrow pointer only appears while the pen is used.

## Reporting

- Say that the new build is running, quoting the PID and start time.
- Pen behaviour can't be verified here. Ask the user to test with the tablet.
- If locking fails after a rebuild, the ad-hoc signature probably changed. The user must re-add the app under System Settings › Privacy & Security › Accessibility.
