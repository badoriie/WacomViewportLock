// Prints the on-screen windows of WacomViewportLock in CG global coordinates (top-left origin).
// Usage: swift .claude/skills/relaunch/list_windows.swift
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let ours = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "WacomViewportLock" }

if ours.isEmpty {
    print("No on-screen WacomViewportLock windows (is the app running and the overlay shown?)")
}
for window in ours {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let pid = window[kCGWindowOwnerPID as String] ?? "?"
    let layer = window[kCGWindowLayer as String] ?? "?"
    print("pid=\(pid) layer=\(layer) x=\(bounds["X"] ?? "?") y=\(bounds["Y"] ?? "?") w=\(bounds["Width"] ?? "?") h=\(bounds["Height"] ?? "?")")
}
