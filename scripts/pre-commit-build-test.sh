#!/usr/bin/env bash
# pre-commit hook: build and test before every commit that touches the app. There is no CI on
# pushes or PRs; the release workflow runs the same checks again before publishing.
set -euo pipefail

# The Command Line Tools alone lack SwiftUI's macro plugin, so the build fails without Xcode.
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
    echo "error: Xcode is required to build and test (SwiftUI macros aren't in the Command Line Tools)." >&2
    echo "Install Xcode, then run: sudo xcode-select -s /Applications/Xcode.app" >&2
    exit 1
fi

swift build --only-use-versions-from-resolved-file
swift test --only-use-versions-from-resolved-file
