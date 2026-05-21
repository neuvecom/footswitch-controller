import Combine
import Foundation

/// KeyEventMonitor のイベントを、現在の frontmost アプリと SettingsStore に
/// 基づいて Action に変換して実行する。
@MainActor
final class ActionDispatcher: ObservableObject {

    /// 直近に実行された Action のログ。設定 UI のデバッグ表示用。
    @Published private(set) var lastDispatch: DispatchRecord?

    struct DispatchRecord: Equatable {
        let date: Date
        let button: FootswitchButton
        let bundleID: String?
        let profileName: String
        let modeName: String
        let action: FootswitchAction
        let executed: Bool
    }

    private let monitor: KeyEventMonitor
    private let appWatcher: AppWatcher
    private let store: SettingsStore
    private let repeater = KeystrokeRepeater()
    private var cancellables: Set<AnyCancellable> = []

    init(monitor: KeyEventMonitor, appWatcher: AppWatcher, store: SettingsStore) {
        self.monitor = monitor
        self.appWatcher = appWatcher
        self.store = store

        // KeyEventMonitor は events 配列の先頭に最新を入れる。差分を観測して
        // ボタン確定済みイベントのみ拾う。
        monitor.$events
            .compactMap { $0.first }
            .removeDuplicates(by: { $0.id == $1.id })
            .sink { [weak self] event in
                guard let self else { return }
                guard let button = event.button else { return }
                self.dispatch(button: button)
            }
            .store(in: &cancellables)
    }

    private func dispatch(button: FootswitchButton) {
        let front = appWatcher.current
        let profile = store.profile(forBundleID: front?.bundleID)
        guard let profile, let mode = profile.activeMode else {
            lastDispatch = DispatchRecord(
                date: Date(), button: button,
                bundleID: front?.bundleID,
                profileName: "(none)",
                modeName: "(none)",
                action: .none,
                executed: false
            )
            return
        }
        let action = mode.action(for: button)
        if case .repeatKeystroke(let code, let mods) = action {
            // 一定時間で自動停止する連射。踏むと開始、もう一度踏むと延長。間隔・継続は固定値。
            repeater.trigger(keyCode: code, modifiers: mods,
                             intervalMs: FootswitchAction.repeatIntervalMs,
                             durationMs: FootswitchAction.repeatDurationMs)
        } else {
            ActionExecutor.execute(action) { [weak self] modeID in
                self?.store.setActiveMode(modeID, in: profile.id)
            }
        }
        lastDispatch = DispatchRecord(
            date: Date(), button: button,
            bundleID: front?.bundleID,
            profileName: profile.displayName,
            modeName: mode.name,
            action: action,
            executed: action != .none
        )
    }
}
