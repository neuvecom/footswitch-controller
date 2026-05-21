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
        case .repeatKeystroke:
            // トグル式連射は状態を持つため ActionDispatcher (KeystrokeRepeater) 側で処理する。
            // ここに来た場合は何もしない。
            break
        case .typeText(let text):
            typeText(text)
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

    /// 遅延なしで即座にキーを送る (トグル連射のタイマー tick 用)。
    /// 連射開始の初回はフットスイッチ自身の F13 keyUp と衝突しうるので、呼び出し側で
    /// 40ms 待ってから最初の tick を始めること。
    static func sendKeystrokeImmediate(keyCode: UInt16, modifiers: ModifierSet) {
        if forbiddenKeyCodes.contains(keyCode) {
            logger.warning("refusing to send forbidden keyCode=\(keyCode)")
            return
        }
        sendViaCGEvent(keyCode: keyCode, modifiers: modifiers)
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


    // MARK: - Type Text

    /// 任意のテキストをそのままタイプする。
    ///
    /// `keyboardSetUnicodeString` で Unicode 文字列を直接流し込むので、キーボード
    /// レイアウト非依存で `\n` のような記号もそのまま入力できる。Accessibility 権限で動く。
    private static func typeText(_ text: String) {
        guard !text.isEmpty else { return }
        logger.info("typeText called length=\(text.count)")

        // フットスイッチの keyUp が通過するのを待ってから送る。
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40)) {
            guard let src = CGEventSource(stateID: .combinedSessionState) else {
                logger.error("failed to create CGEventSource")
                return
            }
            guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else {
                logger.error("failed to create CGEvent for typeText")
                return
            }
            // フットスイッチの修飾(Option/Control)が session state に残っていると
            // Unicode 文字に乗って制御文字化し、入力が無視される。明示的にクリアする。
            keyDown.flags = []
            keyUp.flags = []
            let utf16 = Array(text.utf16)
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            logger.info("post typeText unicode length=\(utf16.count, privacy: .public)")
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
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
