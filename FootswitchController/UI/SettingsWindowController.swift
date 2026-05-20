import AppKit
import SwiftUI

/// 設定 UI を載せる単独 NSWindow。MenuBarExtra から `show()` で開く。
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    let store: SettingsStore
    let appWatcher: AppWatcher

    init(store: SettingsStore, appWatcher: AppWatcher) {
        self.store = store
        self.appWatcher = appWatcher
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(store: store, appWatcher: appWatcher))
        let win = NSWindow(contentViewController: hosting)
        win.title = "Footswitch 設定"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 760, height: 480))
        win.isReleasedWhenClosed = false
        win.center()
        self.window = win
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func handleWindowDidClose() {
        // すべてのウィンドウが閉じたらメニューバーオンリーに戻す。
        if NSApp.windows.allSatisfy({ !$0.isVisible || $0 === window }) {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
