# Contributing to CleanMac

Thanks for your interest. CleanMac is a small single-purpose utility; the bar
is "does one thing well, stays lightweight."

## Dev setup

Requires macOS 15+, Xcode 16+, and [XcodeGen](https://github.com/yonki/XcodeGen).

```sh
brew install xcodegen
xcodegen generate
open CleanMac.xcodeproj
```

Set the signing Team to your Personal Team (target → Signing & Capabilities),
then ⌘R.

## What belongs in CleanMac

- Keyboard / trackpad suppression for cleaning.
- Reliable unlock gesture.
- Native macOS UI (SwiftUI + AppKit as needed).
- Small, focused settings.

## What doesn't

- Cloud sync, accounts, analytics, telemetry.
- AI features.
- Anything that records or transmits input events.

Keep the event-tap callback lightweight and never log keystroke content.

## Pull requests

- Keep diffs small and focused.
- Match the existing code style (SwiftUI patterns in `CleanMac/App.swift`,
  `CleanMac/CleaningMode.swift`, etc).
- Add a test case to `CleanMacTests/UnlockGestureDetectorTests.swift` if you
  change gesture or settings logic.
- The PR template will ask you how you verified the change.

## Reporting issues

Use the issue templates. For bugs, include the macOS version, Mac model, and
CleanMac version from the About window.
