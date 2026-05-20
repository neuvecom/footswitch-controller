import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.luckysama.footswitch-controller", category: "executor")

/// FootswitchAction を実際に実行する。
enum ActionExecutor {

    /// `action` を実行する。`onSwitchMode` は switchMode 系のときに呼ばれる。
    @MainActor
    static func execute(_ action: FootswitchAction, onSwitchMode: (UUID) -> Void) {
        switch action {
        case .none:
            break
        case .keystroke(let keyCode, let mods):
            sendKeystroke(keyCode: keyCode, modifiers: mods)
        case .openURL(let url):
            NSWorkspace.shared.open(url)
        case .runShellScript(let script):
            runShellScript(script)
        case .runAppleScript(let source):
            runAppleScript(source)
        case .switchMode(let modeID):
            onSwitchMode(modeID)
        }
    }

    // MARK: - Keystroke

    /// `kVK_F13` などフットスイッチ自身が送ってくるキーは送出禁止 (無限ループ防止)。
    private static let forbiddenKeyCodes: Set<UInt16> = [105]

    private static func sendKeystroke(keyCode: UInt16, modifiers: ModifierSet) {
        logger.info("sendKeystroke called keyCode=\(keyCode) modifiers=\(modifiers.rawValue, format: .hex)")

        if forbiddenKeyCodes.contains(keyCode) {
            logger.warning("refusing to send forbidden keyCode=\(keyCode) (would re-trigger our own tap)")
            return
        }

        // フットスイッチの keyUp が通過するのを待ってから送る。
        let delay: DispatchTime = .now() + .milliseconds(40)
        DispatchQueue.main.asyncAfter(deadline: delay) {
            sendViaCGEvent(keyCode: keyCode, modifiers: modifiers)
        }
    }

    /// CGEvent でキーを送る。
    ///
    /// Developer ID 署名アプリでは `CGEvent.post` が有効(ad-hoc 署名だと drop される)。
    /// これが効けば System Events 経由(オートメーション権限)が不要になり、必要権限を
    /// 減らせる。Accessibility 権限が必要。
    private static func sendViaCGEvent(keyCode: UInt16, modifiers: ModifierSet) {
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            logger.error("failed to create CGEventSource")
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            logger.error("failed to create CGEvent for keyCode=\(keyCode)")
            return
        }
        let flags = modifiers.cgEventFlags
        keyDown.flags = flags
        keyUp.flags = flags
        logger.info("post CGEvent keyCode=\(keyCode, privacy: .public) flags=\(flags.rawValue, format: .hex, privacy: .public)")
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }


    // MARK: - Scripts

    private static func runShellScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.launchPath = "/bin/zsh"
            process.arguments = ["-c", script]
            do {
                try process.run()
            } catch {
                NSLog("[Footswitch] shell script failed: %@", String(describing: error))
            }
        }
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let script = NSAppleScript(source: source) else { return }
            var errorDict: NSDictionary?
            _ = script.executeAndReturnError(&errorDict)
            if let err = errorDict {
                NSLog("[Footswitch] AppleScript failed: %@", err)
            }
        }
    }
}
