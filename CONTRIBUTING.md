# Contributing

Bug reports and focused pull requests are welcome. Include your macOS version, app mode, timing settings, and steps to reproduce mouse or shortcut issues.

## Project layout

```text
Sources/AutoClickCore/       Mode and burst state machine; no UI dependencies
Sources/AutoClicker/         AppKit/SwiftUI app, mouse events, hotkeys, and login startup
Tests/AutoClickCoreTests/    Swift Testing coverage for the state machine
Resources/                  App metadata and generated app icon
scripts/                    Build, test, install, and icon generation
docs/images/                README screenshots
```

Use macOS and a Swift 6 or later toolchain. There are no third-party package dependencies.

## Making a change

1. Keep the change focused and update the README if behavior changes.
2. Run `./scripts/test.sh` for state-machine and timing changes.
3. Run `./scripts/build.sh` to compile and sign the app.
4. Quit the installed copy and run `"build/Auto Clicker.app/Contents/MacOS/AutoClicker" --self-test` when changing native event handling. The checks use an in-memory event sink; they never send global mouse clicks.
5. Open a pull request describing the resulting behavior and relevant validation.

Add regression coverage for changes to click counts, hold detection, timers, bursts, or release cleanup. Keep generated events distinguishable from physical presses, pair each mouse-down with mouse-up, and preserve manual double-click/triple-click counts while keeping automatic repeats as single clicks.

Use `./scripts/install.sh` to try a change locally. It installs to `~/Applications/Auto Clicker.app`; clicking is off when the updated app launches.

## Refreshing the screenshot

After building, render a preview without activating click modes or changing saved settings:

```sh
"build/Auto Clicker.app/Contents/MacOS/AutoClicker" --render-preview docs/images/menu.png
```
