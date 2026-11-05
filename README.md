# CleanMac

[![Build](https://github.com/dilkushsingh/CleanMac/actions/workflows/build.yml/badge.svg)](https://github.com/dilkushsingh/CleanMac/actions/workflows/build.yml)

Native macOS menu bar utility that temporarily suppresses keyboard and
trackpad input while you clean your Mac. Unlock by holding **Space** + a
physical **trackpad click** for 3 seconds (configurable).

- **Platform:** macOS 15 Sequoia or newer
- **Stack:** Swift, SwiftUI, AppKit, `CGEventTap`
- **No network, no analytics, no telemetry.** Everything stays on your Mac.

## Build

```sh
brew install xcodegen
xcodegen generate
open CleanMac.xcodeproj
```

Hit ⌘R. On first activation macOS will prompt for **Accessibility**
permission — grant it in *System Settings → Privacy & Security →
Accessibility* and try again.

See **[RELEASING.md](RELEASING.md)** for distributing to other Macs
(ad-hoc vs. Developer ID + notarization).

## Test

```sh
xcodebuild test -scheme CleanMac -destination 'platform=macOS'
```

## Settings

- Launch at login (via `SMAppService.mainApp`)
- Automatic unlock timeout: 1 min – 5 min, 30 s steps, default 2 min
- Unlock hold duration: 2 – 5 s, 0.5 s steps, default 3 s
- Overlay appearance: System / Light / Dark

Values are persisted in `UserDefaults` and normalized to the supported range
on load.

## Project layout

```
CleanMac/                    # app sources
  App.swift                  # entry point, MenuBarExtra, Settings + About scenes
  CleaningMode.swift         # manager, state, AppSettings, SettingsView
  InputMonitor.swift         # CGEventTap owner + UnlockGestureDetector
  Overlay.swift              # NSPanel at .screenSaver level + SwiftUI overlay
  Permissions.swift          # AX trust check + settings deeplink
  Info.plist
CleanMacTests/               # XCTest suite
  UnlockGestureDetectorTests.swift
scripts/
  package-release.sh         # build + zip for distribution
.github/
  workflows/build.yml        # CI: build + test on every push / PR
  ISSUE_TEMPLATE/            # bug + feature templates
  pull_request_template.md
project.yml                  # XcodeGen spec (source of truth)
RELEASING.md                 # release / signing / notarization notes
CONTRIBUTING.md
```

## Safety

- Only enters `locked` after the event tap is created and enabled.
- Sleep notification triggers fail-open.
- `tapDisabledByTimeout` is re-enabled; `tapDisabledByUserInput` fails open.
- Auto-unlock timer runs independently of input and is snapshotted at
  activation (changing the setting mid-lock cannot spawn a second timer).
- Nothing is logged about keystroke content; no network calls anywhere.

## Troubleshooting

### macOS keeps asking for Accessibility permission on every build

macOS keys the grant to the app's code signature. Each rebuild without a
stable signing Team produces a new ad-hoc signature, so macOS treats it as a
different app.

Fix:

1. In Xcode: target → **Signing & Capabilities** → set **Team** to your
   Personal Team.
2. **System Settings → Privacy & Security → Accessibility** → remove any
   stale CleanMac entries.
3. ⌘R once, grant the prompt. Future builds inherit the grant.

### Settings or About window opens behind other apps

CleanMac is an `LSUIElement` (menu-bar-only) app, so macOS doesn't elevate it
automatically. The window is briefly set to `.floating` to pop forward, then
dropped to `.normal` when it loses key focus so you can send it behind other
apps normally.

### Opening Settings / About from another app's fullscreen Space

macOS switches you back to the desktop Space — standard behavior for menu-bar
utilities. Overlaying a fullscreen Space requires an NSPanel-based rewrite of
the Settings/About windows.

## License

TBD.
