# CleaningMode (Mac Screen Cleaning Mode)

A distraction-free full-screen mode for cleaning your Mac display, inspired by Tesla's Screen Cleaning Mode.

## Features
- Full-screen black UI with Tesla-like typography
- Swallows all keyboard input except the exit combo
- Exit by holding `⌘ + Esc` for 2 seconds (with on-screen ring)
- Sparkling star animation on exit, then the app quits
- No special permissions required

## Usage
1. Build and run the macOS app.
2. The window enters full screen automatically.
3. Clean the screen; keyboard input is blocked.
4. Hold `⌘ + Esc` for ~2 seconds until the ring completes to exit.

## Notes
- Keyboard interception uses local event monitors within the app only; it does not require Accessibility permission.
- If full screen does not toggle on first launch due to focus timing, relaunch the app.

## Code Map
- `CleaningModeApp.swift`: Window setup with hidden title bar and full-screen host.
- `ContentView.swift`: UI, keyboard intercept, hold-to-exit logic, sparkle animation.
