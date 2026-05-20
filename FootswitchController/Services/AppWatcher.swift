import AppKit
import Combine
import Foundation

struct FrontmostApp: Equatable {
    let bundleID: String?
    let localizedName: String

    init?(_ app: NSRunningApplication?) {
        guard let app else { return nil }
        self.bundleID = app.bundleIdentifier
        self.localizedName = app.localizedName ?? "Unknown"
    }
}

/// frontmost (最前面) のアプリを購読・公開する。
///
/// 設定ウィンドウを開いた瞬間など、FootswitchController 自身が frontmost に
/// なるタイミングがある。そのときに `current` を自分自身で上書きしてしまうと、
/// フットスイッチを踏んだ時に「フォアグラウンドアプリ用のキーマップ」が
/// 引けなくなるため、自分自身は無視して直前のアプリを保持する。
@MainActor
final class AppWatcher: ObservableObject {
    @Published private(set) var current: FrontmostApp?

    private var observers: [NSObjectProtocol] = []
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        if let initial = FrontmostApp(NSWorkspace.shared.frontmostApplication),
           initial.bundleID != ownBundleID {
            current = initial
        }

        let center = NSWorkspace.shared.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // queue: .main 指定なのでこのクロージャはメインで実行されるが、
            // コンパイラに MainActor isolation を伝えるため assumeIsolated する。
            MainActor.assumeIsolated {
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let next = FrontmostApp(app) else { return }
                // 自分自身が前面になった場合は無視 (直前のアプリを保持)。
                if next.bundleID == self.ownBundleID { return }
                self.current = next
            }
        }
        observers.append(token)
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for token in observers { center.removeObserver(token) }
    }
}
