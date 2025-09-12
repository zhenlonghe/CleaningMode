# CleaningMode (Mac Screen Cleaning Mode)

A distraction-free full-screen mode for cleaning your Mac display, inspired by Tesla's Screen Cleaning Mode.

## Features
- Full-screen black UI with Tesla-like typography
- Keyboard lock with permission gating: blocks all keys except `⌘ + Esc` when authorized
- Exit by holding `⌘ + Esc` until the ring completes (about 0.6s by default)
- Sparkling star animation on exit, then the app quits
- Universal binary: runs on Apple Silicon (arm64) and Intel (x86_64)

## Usage
1. Build and run the macOS app.
2. The window covers all displays automatically.
3. Clean the screen.
4. Hold `⌘ + Esc` until the ring completes to exit.

## Permissions
- Accessibility (System Settings → Privacy & Security → Accessibility)
  - Required to start cleaning mode.
  - Used to observe modifier keys and ensure the exit gesture works reliably.

- Input Monitoring (optional)
  - You generally do not need it. The app can function without it.
  - Granting it may improve key interception on some setups, but is not required.

## Notes
- If full screen does not toggle on first launch due to focus timing, relaunch the app.
- The app will automatically bring system permission dialogs to the foreground for better visibility.

## Code Map
- `CleaningModeApp.swift`: Window setup with hidden title bar and full-screen host.
- `ContentView.swift`: UI, keyboard binder, hold-to-exit logic, sparkle animation.
- `KeyboardLockManager.swift`: Permission-aware keyboard lock (global tap with fallback to local monitors).
