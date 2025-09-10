//
//  ContentView.swift
//  CleaningMode
//
//  Created by Zhenlong on 2025/9/9.
//

import SwiftUI
import Combine
import AppKit

// MARK: - Aphorism Provider
struct AphorismProvider {
    private static let phrases: [String] = [
        "Clear screen. Clear mind.",
        "Order outside, clarity within.",
        "Cleanliness is a form of calm.",
        "Wipe the glass, quiet the mind.",
        "Simplicity clears the view.",
        "A clear surface invites clear thought.",
        "Let dust settle; let thoughts rise.",
        "In tidiness, we find attention.",
        "Small acts, quiet minds.",
        "Less noise, more notice.",
        "Clear space, steady focus.",
        "Remove dust, reveal intent.",
        "Polished glass, present mind.",
        "Empty surface, open attention.",
        "Gentle care, greater clarity.",
        "Still hands, still mind.",
        "Quiet the smear, quiet the self.",
        "Clear the pane, see the point.",
        "Unclutter the view, uncloud the mind.",
        "Simplicity is depth made visible.",
        "Make it clear, make it calm.",
        "Clean without haste; see without strain.",
        "The clearer the glass, the nearer the now.",
        "Neat surface, neat thinking."
    ]

    private static let cached: String = {
        phrases.randomElement() ?? "Clear screen. Clear mind."
    }()

    static func current() -> String { cached }
}

// MARK: - ContentView
struct ContentView: View {
    var isAuxiliary: Bool = false
    @State private var isCommandHeld: Bool = false
    @State private var isEscapeHeld: Bool = false
    @State private var exitProgress: Double = 0
    @State private var holdTimer: AnyCancellable?
    @State private var showSparkles: Bool = false
    @State private var hasRequestedFullscreen: Bool = false

    private let requiredHoldSeconds: Double = 0.6

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Solid black background (fully opaque)
                Color.black
                    .ignoresSafeArea()

                // Centered copy
                VStack(alignment: .center, spacing: 14) {
                    Text("Cleaning Mode")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white.opacity(0.95))

                    Text(AphorismProvider.current())
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(maxWidth: min(520, proxy.size.width * 0.8))
                        .multilineTextAlignment(.center)
                    // Hold to exit hint (text always visible; ring appears on hold)
                    HStack(spacing: 12) {
                        if (isCommandHeld && isEscapeHeld) || exitProgress > 0 {
                            ExitProgressRing(progress: exitProgress)
                                .frame(width: 18, height: 18)
                                .transition(.opacity)
                        }

                        HStack(spacing: 8) {
                            Text("Hold")
                                .font(.system(size: 14, weight: .semibold))
                            KeyCap(label: "⌘")
                            Text("+")
                                .font(.system(size: 14, weight: .semibold))
                            KeyCap(label: "esc")
                            Text("to exit")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .accessibilityLabel("Hold Command and Escape for 1.5 seconds to exit")
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                // Sparkle animation overlay on exit
                if showSparkles {
                    SparkleField()
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .overlay(
                Group {
                    if !isAuxiliary {
                        // Install NSEvent monitors and swallow keys (only once)
                        KeyboardInterceptor(
                            onFlagsChanged: { flags in
                                isCommandHeld = flags.contains(.command)
                                updateHoldState()
                            },
                            onKeyDown: { keyCode in
                                // 53 is Escape on macOS
                                if keyCode == 53 {
                                    isEscapeHeld = true
                                    updateHoldState()
                                }
                            },
                            onKeyUp: { keyCode in
                                if keyCode == 53 {
                                    isEscapeHeld = false
                                    updateHoldState()
                                }
                            }
                        )
                    }
                }
            )
            .onAppear {
                if !isAuxiliary {
                    NSCursor.hide()
                    presentAcrossAllScreensIfNeeded()
                }
            }
        }
    }

    // MARK: - Hold logic
    private func updateHoldState() {
        let bothHeld = isCommandHeld && isEscapeHeld
        if bothHeld {
            if holdTimer == nil {
                exitProgress = 0
                let start = Date()
                holdTimer = Timer.publish(every: 0.016, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        let elapsed = Date().timeIntervalSince(start)
                        exitProgress = min(1.0, elapsed / requiredHoldSeconds)
                        if exitProgress >= 1.0 {
                            holdTimer?.cancel()
                            holdTimer = nil
                            performExitSequence()
                        }
                    }
            }
        } else {
            holdTimer?.cancel()
            holdTimer = nil
            withAnimation(.easeOut(duration: 0.18)) {
                exitProgress = 0
            }
        }
    }

    private func performExitSequence() {
        withAnimation(.easeOut(duration: 0.25)) {
            showSparkles = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            NSCursor.unhide()
            MultiDisplayManager.shared.closeAuxiliaryWindows()
            NSApp.terminate(nil)
        }
    }

    private func presentAcrossAllScreensIfNeeded() {
        guard !hasRequestedFullscreen else { return }
        hasRequestedFullscreen = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            MultiDisplayManager.shared.setupAllScreens()
        }
    }
}

// MARK: - Exit Progress Ring
private struct ExitProgressRing: View {
    var progress: Double
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.016), value: progress)
        }
    }
}

// MARK: - Sparkle Field
private struct SparkleField: View {
    @State private var items: [Sparkle] = (0..<60).map { _ in Sparkle.random() }
    @State private var animate: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(items) { item in
                    Image(systemName: "star.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: item.size, height: item.size)
                        .foregroundColor(.white.opacity(item.opacity))
                        .position(x: item.x * proxy.size.width, y: item.y * proxy.size.height)
                        .scaleEffect(animate ? item.scale : 0.1)
                        .opacity(animate ? 0 : 1)
                        .rotationEffect(.degrees(item.rotation))
                        .blendMode(.screen)
                        .animation(.easeOut(duration: 0.6).delay(item.delay), value: animate)
                }
            }
            .onAppear {
                animate = true
            }
        }
    }
}

private struct Sparkle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
    let rotation: Double
    let delay: Double
    let scale: CGFloat

    static func random() -> Sparkle {
        Sparkle(
            x: .random(in: 0...1),
            y: .random(in: 0...1),
            size: .random(in: 3...10),
            opacity: .random(in: 0.6...1.0),
            rotation: .random(in: 0...360),
            delay: .random(in: 0...0.2),
            scale: .random(in: 2.2...3.4)
        )
    }
}

// MARK: - NSEvent Interceptor
private struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            )
    }
}

// MARK: - NSEvent Interceptor
private struct KeyboardInterceptor: NSViewRepresentable {
    var onFlagsChanged: (NSEvent.ModifierFlags) -> Void
    var onKeyDown: (UInt16) -> Void
    var onKeyUp: (UInt16) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.installMonitors()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFlagsChanged: onFlagsChanged, onKeyDown: onKeyDown, onKeyUp: onKeyUp)
    }

    final class Coordinator {
        private var flagsMonitor: Any?
        private var downMonitor: Any?
        private var upMonitor: Any?

        private let onFlagsChanged: (NSEvent.ModifierFlags) -> Void
        private let onKeyDown: (UInt16) -> Void
        private let onKeyUp: (UInt16) -> Void

        init(onFlagsChanged: @escaping (NSEvent.ModifierFlags) -> Void,
             onKeyDown: @escaping (UInt16) -> Void,
             onKeyUp: @escaping (UInt16) -> Void) {
            self.onFlagsChanged = onFlagsChanged
            self.onKeyDown = onKeyDown
            self.onKeyUp = onKeyUp
        }

        deinit {
            removeMonitors()
        }

        func installMonitors() {
            removeMonitors()
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                self.onFlagsChanged(event.modifierFlags)
                return nil // swallow
            }
            downMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                self.onKeyDown(event.keyCode)
                return nil // swallow everything
            }
            upMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { event in
                self.onKeyUp(event.keyCode)
                return nil
            }
        }

        private func removeMonitors() {
            if let m = flagsMonitor { NSEvent.removeMonitor(m) }
            if let m = downMonitor { NSEvent.removeMonitor(m) }
            if let m = upMonitor { NSEvent.removeMonitor(m) }
            flagsMonitor = nil
            downMonitor = nil
            upMonitor = nil
        }
    }
}

// MARK: - Multiple Display Windows
final class MultiDisplayManager {
    static let shared = MultiDisplayManager()
    private var auxiliaryWindows: [NSWindow] = []
    private weak var primaryWindow: NSWindow?

    func setupAllScreens() {
        closeAuxiliaryWindows()
        let allScreens = NSScreen.screens
        let window = NSApp.keyWindow ?? NSApp.windows.first
        guard let primaryWindow = window else { return }
        self.primaryWindow = primaryWindow

        // Resize primary window to cover its screen
        if let mainScreen = primaryWindow.screen ?? NSScreen.main {
            primaryWindow.styleMask = [.borderless]
            primaryWindow.isOpaque = true
            primaryWindow.hasShadow = false
            primaryWindow.titleVisibility = .hidden
            primaryWindow.titlebarAppearsTransparent = true
            primaryWindow.backgroundColor = .black
            primaryWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            primaryWindow.level = .screenSaver
            primaryWindow.setFrame(mainScreen.frame, display: true)
            primaryWindow.orderFrontRegardless()
        }

        // Create borderless windows for other screens
        for screen in allScreens {
            if screen == primaryWindow.screen { continue }
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.styleMask = [.borderless]
            window.isOpaque = true
            window.backgroundColor = .black
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.ignoresMouseEvents = true
            window.contentView = NSHostingView(rootView: ContentView(isAuxiliary: true))
            window.orderFrontRegardless()
            auxiliaryWindows.append(window)
        }
    }

    func closeAuxiliaryWindows() {
        auxiliaryWindows.forEach { $0.close() }
        auxiliaryWindows.removeAll()
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
