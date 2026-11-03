# Changelog

All notable changes to WacomViewportLock. New entries are written by
[release-please](https://github.com/googleapis/release-please) from the Conventional Commit
titles of merged pull requests.

## [0.2.1](https://github.com/badoriie/WacomViewportLock/compare/v0.2.0...v0.2.1) (2026-11-03)


### Build & Release

* release with release-please, check with pre-commit instead of CI ([#5](https://github.com/badoriie/WacomViewportLock/issues/5)) ([bfb0db5](https://github.com/badoriie/WacomViewportLock/commit/bfb0db5bf4e7074bda2c95eb90a2cca1460bdb51))

## [0.2.0](https://github.com/badoriie/WacomViewportLock/compare/v0.1.0...v0.2.0) (2026-11-03)

### Features

* Automatic updates with Sparkle: a daily background check, and **Check for Updates…** in the menu bar menu. Only stable releases are offered ([#4](https://github.com/badoriie/WacomViewportLock/pull/4)).

### Build & Release

* Releases publish a signed `appcast.xml` for Sparkle next to the DMG and zip ([#4](https://github.com/badoriie/WacomViewportLock/pull/4)).

## [0.1.0](https://github.com/badoriie/WacomViewportLock/releases/tag/v0.1.0) (2026-11-03)

### Features

* Floating overlay with the aspect ratio and physical size of the Wacom tablet, with 1:1 physical-size mode on by default.
* Lock mode remaps pen input 1:1 into the overlay. After unlocking, the pen keeps working in relative mouse mode.
* Calibration: tablet size, tablet-to-monitor mapping and per-monitor screen-scale correction with a ruler measurement.
* Menu bar menu with lock, overlay visibility and opacity, and the global hotkey ⌃⌥⌘L.
