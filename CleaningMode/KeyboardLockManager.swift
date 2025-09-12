//
//  KeyboardLockManager.swift
//  CleaningMode
//
//  Created by Assistant on 2025/9/11.
//

import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

final class KeyboardLockManager {
    static let shared = KeyboardLockManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning: Bool = false
    private(set) var isUsingGlobalTap: Bool = false

    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?
    private var keyUpMonitor: Any?
    private var didPromptForPermission: Bool = false

    private var isCommandHeld: Bool = false

    // Callbacks for UI state updates
    var onFlagsChanged: ((Bool) -> Void)? // isCommandHeld
    var onKeyDown: ((UInt16) -> Void)? // keyCode
    var onKeyUp: ((UInt16) -> Void)? // keyCode

    private init() {}

    func start() {
        guard !isRunning else { return }

        // Try to install global event tap first (requires Input Monitoring permission)
        if installGlobalEventTapIfPossible() {
            isRunning = true
            isUsingGlobalTap = true
            return
        }

        // Fallback: local monitors (do NOT swallow keys). Keep current app behavior.
        installLocalMonitors()
        isRunning = true
        isUsingGlobalTap = false

        // Optionally guide user to grant permission (one-time)
        if !didPromptForPermission {
            promptForInputMonitoringPermission()
            didPromptForPermission = true
        }
    }

    func stop() {
        guard isRunning else { return }
        // Tear down global tap if present
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        // Tear down local monitors if present
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = keyDownMonitor { NSEvent.removeMonitor(m) }
        if let m = keyUpMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
        keyDownMonitor = nil
        keyUpMonitor = nil

        isRunning = false
        isCommandHeld = false
    }

    func hasInputMonitoringPermission() -> Bool {
        // Try to create a minimal event tap to test permission
        let testMask = 1 << CGEventType.keyDown.rawValue
        let testTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(testMask),
            callback: { _, _, event, _ in
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        )
        
        if let tap = testTap {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }
    
    func promptForInputMonitoringPermission() {
        // System Settings → Privacy & Security → Input Monitoring
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // Accessibility (Assistive) permission check/open
    func hasAccessibilityPermission() -> Bool {
        // Do not prompt here to avoid unexpected system alerts; just check trust state
        return AXIsProcessTrusted()
    }

    /// Shows the official Accessibility permission system alert.
    /// Calling this helps the app appear in the Accessibility list.
    func requestAccessibilityPermissionPrompt() {
        // First, try to access accessibility features to register the app
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Also try to create a temporary accessibility element to ensure registration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.ensureAccessibilityRegistration()
        }
    }
    
    private func ensureAccessibilityRegistration() {
        // Try to access the main window's accessibility element
        if NSApp.keyWindow != nil {
            let element = AXUIElementCreateApplication(getpid())
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value)
            // This call helps register the app even if it fails
            _ = result
        }
    }

    func openAccessibilitySettings() {
        // First, ensure the app is registered for accessibility permissions
        // by creating a temporary event tap that will register us with TCC
        primeInputMonitoringRegistration()
        
        // Trigger the system permission dialog first
        requestAccessibilityPermissionPrompt()
        
        // Then open System Settings as a fallback after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
                
                // Bring System Settings to foreground after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.bringSystemSettingsToForeground()
                }
            }
        }
    }
    
    private func bringSystemSettingsToForeground() {
        // Find System Settings window and bring it to front
        let runningApps = NSWorkspace.shared.runningApplications
        if let systemSettings = runningApps.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" || $0.bundleIdentifier == "com.apple.SystemSettings" }) {
            systemSettings.activate(options: [.activateAllWindows])
        }
        
        // Use a simpler approach to ensure the app is visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Try to bring our app to front briefly to ensure user sees the permission dialog
            NSApp.activate(ignoringOtherApps: true)
            
            // Then bring System Settings back to front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let systemSettings = runningApps.first(where: { $0.bundleIdentifier == "com.apple.systempreferences" || $0.bundleIdentifier == "com.apple.SystemSettings" }) {
                    systemSettings.activate(options: [.activateAllWindows])
                }
            }
        }
    }

    /// Attempt to create a short-lived event tap to ensure TCC registers the app
    /// under Input Monitoring. This does not keep the tap alive.
    func primeInputMonitoringRegistration() {
        // Try both HID and session event taps to ensure registration
        let mask = 1 << CGEventType.keyDown.rawValue
        let locations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        
        for location in locations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: { _, _, event, _ in
                    return Unmanaged.passUnretained(event)
                },
                userInfo: nil
            ) {
                // Creating the tap is enough to make TCC notice us. Immediately invalidate.
                CFMachPortInvalidate(tap)
                break // Only need one successful registration
            }
        }
    }

    // MARK: - Private helpers
    private func installGlobalEventTapIfPossible() -> Bool {
        // Include NX_SYSDEFINED (14) to try intercepting media/brightness keys
        let NX_SYSDEFINED: UInt64 = 14
        let mask = (
            1 << CGEventType.keyDown.rawValue |
            1 << CGEventType.keyUp.rawValue |
            1 << CGEventType.flagsChanged.rawValue |
            1 << NX_SYSDEFINED
        )

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let managerPtr = refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<KeyboardLockManager>.fromOpaque(managerPtr).takeUnretainedValue()

            // Intercept system-defined (media/brightness) events by raw value if present
            if type.rawValue == 14 { // NX_SYSDEFINED
                return nil // swallow
            }

            switch type {
            case .flagsChanged:
                let flags = event.flags
                let commandHeld = flags.contains(.maskCommand)
                manager.isCommandHeld = commandHeld
                manager.onFlagsChanged?(commandHeld)
                return nil // swallow
            case .keyDown:
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if manager.isCommandHeld && keyCode == 53 { // Escape
                    manager.onKeyDown?(keyCode)
                    return Unmanaged.passUnretained(event)
                } else {
                    manager.onKeyDown?(keyCode)
                    // Block all keys including function keys (F1-F12: keycodes 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111)
                    return nil // swallow others
                }
            case .keyUp:
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                if manager.isCommandHeld && keyCode == 53 { // Escape
                    manager.onKeyUp?(keyCode)
                    return Unmanaged.passUnretained(event)
                } else {
                    manager.onKeyUp?(keyCode)
                    // Block all keys including function keys
                    return nil // swallow others
                }
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap = manager.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            default:
                return Unmanaged.passUnretained(event)
            }
        }

        let ref = Unmanaged.passUnretained(self).toOpaque()
        // Prefer HID tap for lowest-level interception (e.g., brightness/volume keys), fallback to session tap
        let candidateTaps: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        for location in candidateTaps {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: callback,
                userInfo: ref
            ) {
                eventTap = tap
                if let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) {
                    runLoopSource = source
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                    CGEvent.tapEnable(tap: tap, enable: true)
                    return true
                } else {
                    CFMachPortInvalidate(tap)
                    eventTap = nil
                }
            }
        }
        return false
    }

    private func installLocalMonitors() {
        // Local monitors pass events through (do not swallow). This keeps current behavior
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let commandHeld = event.modifierFlags.contains(.command)
            self?.isCommandHeld = commandHeld
            self?.onFlagsChanged?(commandHeld)
            return event // pass through
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt16(event.keyCode)
            self?.onKeyDown?(keyCode)
            return event // pass through
        }
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            let keyCode = UInt16(event.keyCode)
            self?.onKeyUp?(keyCode)
            return event // pass through
        }
        
        // Note: Local monitors cannot intercept system-defined events (function keys)
        // Only global event taps with Input Monitoring permission can block those
    }
    
    /// Helper method to reset permissions for testing clean install scenarios
    /// This will remove the app from all permission lists
    func resetPermissionsForTesting() {
        // Note: This is for development/testing only
        // In production, users would need to manually remove permissions from System Settings
        print("To simulate a clean install:")
        print("1. Go to System Settings > Privacy & Security > Accessibility")
        print("2. Remove CleaningMode from the list if present")
        print("3. Go to System Settings > Privacy & Security > Input Monitoring")
        print("4. Remove CleaningMode from the list if present")
        print("5. Restart the app to test clean install flow")
    }
}


