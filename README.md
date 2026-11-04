# CleanMac

Native macOS menu bar utility that temporarily suppresses keyboard and
trackpad input while you clean your Mac. Unlock by holding **Space** + a
physical **trackpad click** for 3 seconds (configurable).

## Build

```sh
brew install xcodegen
xcodegen generate
open CleanMac.xcodeproj
```

Hit ⌘R. On first activation macOS will prompt for **Accessibility**
permission — grant it in *System Settings → Privacy & Security →
Accessibility* and try again.

## Test

```sh
xcodebuild test -scheme CleanMac -destination 'platform=macOS'
```

## Settings

* Launch at login (via `SMAppService.mainApp`)
* Automatic unlock timeout: 30 s – 10 min, 30 s steps, default 2 min
* Unlock hold duration: 2 – 5 s, 0.5 s steps, default 3 s
* Overlay appearance: System / Light / Dark

Values are persisted in `UserDefaults` and normalized to the supported range
on load.

## Project layout

```
CleanMac/
  App.swift          # entry point, MenuBarExtra, Settings + About scenes
  CleaningMode.swift # manager, state, AppSettings, SettingsView
  InputMonitor.swift # CGEventTap owner + UnlockGestureDetector
  Overlay.swift      # NSPanel at .screenSaver level + SwiftUI overlay
  Permissions.swift  # AX trust check + settings deeplink
  Info.plist
CleanMacTests/
  UnlockGestureDetectorTests.swift
project.yml          # XcodeGen spec
```

## Safety

* Only enters `locked` after the event tap is created and enabled.
* Sleep notification triggers fail-open.
* `tapDisabledByTimeout` is re-enabled; `tapDisabledByUserInput` fails open.
* Auto-unlock timer runs independently of input and is snapshotted at
  activation (changing the setting mid-lock cannot spawn a second timer).
* Nothing is logged about keystroke content; no network calls anywhere.
