import Foundation
import ServiceManagement
import OSLog

private let logger = Logger(subsystem: "com.luckysama.footswitch-controller", category: "loginitem")

/// 「ログイン時に起動」(ログイン項目) の登録状態を管理する。
///
/// macOS 13+ の `SMAppService.mainApp` を使う。Developer ID 署名アプリなら追加の
/// entitlement や helper は不要で、アプリ本体をそのままログイン項目に登録できる。
@MainActor
final class LoginItemManager: ObservableObject {
    /// 現在ログイン項目として有効か。
    @Published private(set) var isEnabled: Bool = false

    init() {
        refresh()
    }

    /// 実際の登録状態を読み直す。
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// 登録 / 解除を切り替える。
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            logger.info("login item set enabled=\(enabled, privacy: .public)")
        } catch {
            logger.error("login item toggle failed: \(String(describing: error), privacy: .public)")
        }
        refresh()
    }
}
