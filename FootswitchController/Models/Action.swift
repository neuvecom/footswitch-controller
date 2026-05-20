import CoreGraphics
import Foundation

/// 1 ボタン押下に対して実行されるアクション。
enum FootswitchAction: Codable, Hashable {
    case none
    case keystroke(keyCode: UInt16, modifiers: ModifierSet)
    case typeText(String)
    case openURL(URL)
    case runShellScript(String)
    case runAppleScript(String)
    case switchMode(UUID)

    var displayName: String {
        switch self {
        case .none: return "なし"
        case .keystroke(let code, let mods):
            let modString = mods.symbolString
            let keyName = KeyCodes.name(for: code) ?? "key(\(code))"
            return modString.isEmpty ? keyName : "\(modString)\(keyName)"
        case .typeText(let text): return "Type \"\(text)\""
        case .openURL(let url): return "Open \(url.absoluteString)"
        case .runShellScript: return "Shell Script"
        case .runAppleScript: return "AppleScript"
        case .switchMode: return "Switch Mode"
        }
    }

    var typeLabel: String {
        switch self {
        case .none: return "None"
        case .keystroke: return "Keystroke"
        case .typeText: return "Type Text"
        case .openURL: return "Open URL"
        case .runShellScript: return "Shell"
        case .runAppleScript: return "AppleScript"
        case .switchMode: return "Switch Mode"
        }
    }
}

/// アクションの種類だけを表す列挙 (UI のドロップダウン用)。
enum ActionKind: String, CaseIterable, Identifiable {
    case none, keystroke, typeText, openURL, runShellScript, runAppleScript, switchMode
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "なし"
        case .keystroke: return "キーストローク"
        case .typeText: return "テキストを打つ"
        case .openURL: return "URL を開く"
        case .runShellScript: return "Shell スクリプト"
        case .runAppleScript: return "AppleScript"
        case .switchMode: return "モード切替"
        }
    }

    static func kind(of action: FootswitchAction) -> ActionKind {
        switch action {
        case .none: return .none
        case .keystroke: return .keystroke
        case .typeText: return .typeText
        case .openURL: return .openURL
        case .runShellScript: return .runShellScript
        case .runAppleScript: return .runAppleScript
        case .switchMode: return .switchMode
        }
    }
}

/// 修飾キーの組み合わせ。CGEventFlags へ変換可能。
struct ModifierSet: OptionSet, Codable, Hashable {
    let rawValue: UInt

    static let command  = ModifierSet(rawValue: 1 << 0)
    static let option   = ModifierSet(rawValue: 1 << 1)
    static let control  = ModifierSet(rawValue: 1 << 2)
    static let shift    = ModifierSet(rawValue: 1 << 3)

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    var symbolString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }
}

/// 編集 UI で使うキーのプリセット。
/// 完全なキーマップではなく、よく使うものだけ。
enum KeyCodes {
    static let presets: [(code: UInt16, name: String)] = [
        // letters
        (0, "A"), (11, "B"), (8, "C"), (2, "D"), (14, "E"),
        (3, "F"), (5, "G"), (4, "H"), (34, "I"), (38, "J"),
        (40, "K"), (37, "L"), (46, "M"), (45, "N"), (31, "O"),
        (35, "P"), (12, "Q"), (15, "R"), (1, "S"), (17, "T"),
        (32, "U"), (9, "V"), (13, "W"), (7, "X"), (16, "Y"), (6, "Z"),
        // numbers
        (29, "0"), (18, "1"), (19, "2"), (20, "3"), (21, "4"),
        (23, "5"), (22, "6"), (26, "7"), (28, "8"), (25, "9"),
        // navigation / editing
        (36, "Return"), (48, "Tab"), (49, "Space"), (51, "Delete"),
        (53, "Escape"), (76, "Enter (Numpad)"),
        (123, "Left"), (124, "Right"), (125, "Down"), (126, "Up"),
        (115, "Home"), (119, "End"),
        (116, "PageUp"), (121, "PageDown"),
        // function
        (122, "F1"), (120, "F2"), (99, "F3"), (118, "F4"),
        (96, "F5"), (97, "F6"), (98, "F7"), (100, "F8"),
        (101, "F9"), (109, "F10"), (103, "F11"), (111, "F12"),
        // punctuation (US layout)
        (27, "-"), (24, "="), (33, "["), (30, "]"), (42, "\\"),
        (41, ";"), (39, "'"), (43, ","), (47, "."), (44, "/"), (50, "`"),
    ]

    static func name(for code: UInt16) -> String? {
        presets.first(where: { $0.code == code })?.name
    }
}
