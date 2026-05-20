import AppKit
import SwiftUI

/// オンボーディング UI を載せる単独 NSWindow。
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let monitor: KeyEventMonitor

    init(monitor: KeyEventMonitor) {
        self.monitor = monitor
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView(monitor: monitor) { [weak self] in
            self?.close()
        }
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "ようこそ"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        self.window = win
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
        window = nil
        // ウィンドウが他に無ければメニューバーオンリーに戻す。
        if NSApp.windows.allSatisfy({ !$0.isVisible }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
