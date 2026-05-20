import SwiftUI

@main
struct FootswitchControllerApp: App {
    @StateObject private var monitor: KeyEventMonitor
    @StateObject private var appWatcher: AppWatcher
    @StateObject private var store: SettingsStore
    @StateObject private var dispatcherHolder: DispatcherHolder
    @StateObject private var updateChecker: UpdateChecker

    private let settingsWindow: SettingsWindowController
    private let onboardingWindow: OnboardingWindowController

    init() {
        let monitor = KeyEventMonitor()
        let appWatcher = AppWatcher()
        let store = SettingsStore()
        let dispatcher = ActionDispatcher(monitor: monitor, appWatcher: appWatcher, store: store)
        let updateChecker = UpdateChecker()

        _monitor = StateObject(wrappedValue: monitor)
        _appWatcher = StateObject(wrappedValue: appWatcher)
        _store = StateObject(wrappedValue: store)
        _dispatcherHolder = StateObject(wrappedValue: DispatcherHolder(dispatcher: dispatcher))
        _updateChecker = StateObject(wrappedValue: updateChecker)

        self.settingsWindow = SettingsWindowController(store: store, appWatcher: appWatcher)
        self.onboardingWindow = OnboardingWindowController(monitor: monitor)

        // アクセシビリティ権限が無ければ初回オンボーディングを表示。
        if !monitor.hasAccessibilityPermission {
            let onboarding = onboardingWindow
            DispatchQueue.main.async {
                onboarding.show()
            }
        }

        // 起動時にアップデートを確認。
        Task { await updateChecker.check() }
    }

    var body: some Scene {
        MenuBarExtra("Footswitch", systemImage: "keyboard") {
            MenuBarContentView(
                monitor: monitor,
                appWatcher: appWatcher,
                store: store,
                dispatcher: dispatcherHolder.dispatcher,
                updateChecker: updateChecker,
                openSettings: { settingsWindow.show() },
                openOnboarding: { onboardingWindow.show() }
            )
        }
        .menuBarExtraStyle(.window)
    }
}

/// `ActionDispatcher` を `StateObject` として保持するためのラッパ。
@MainActor
final class DispatcherHolder: ObservableObject {
    let dispatcher: ActionDispatcher
    init(dispatcher: ActionDispatcher) { self.dispatcher = dispatcher }
}
