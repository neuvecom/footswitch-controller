import Foundation

/// 1 アプリ (または Default) に対する設定。
///
/// 複数の `Mode` を持ち、`activeModeID` が現在使われるモード。
struct Profile: Identifiable, Codable, Hashable {
    var id: UUID
    /// `nil` の場合は「どのアプリにもマッチする」デフォルトプロフィール。
    var bundleID: String?
    var displayName: String
    var modes: [Mode]
    var activeModeID: UUID

    init(id: UUID = UUID(), bundleID: String?, displayName: String, modes: [Mode]) {
        self.id = id
        self.bundleID = bundleID
        self.displayName = displayName
        self.modes = modes
        self.activeModeID = modes.first?.id ?? UUID()
    }

    var isDefault: Bool { bundleID == nil }

    var activeMode: Mode? {
        modes.first(where: { $0.id == activeModeID }) ?? modes.first
    }

    static func makeDefault() -> Profile {
        Profile(
            bundleID: nil,
            displayName: "Default",
            modes: [Mode.makeEmpty(name: "Default")]
        )
    }

    static func make(for bundleID: String, displayName: String) -> Profile {
        Profile(
            bundleID: bundleID,
            displayName: displayName,
            modes: [Mode.makeEmpty(name: "Default")]
        )
    }
}

/// プロフィール内のキーマップ。
///
/// button1〜3 が 1 台目 (F13系)、button4〜6 が 2 台目 (F18系) に対応する。
/// 4〜6 は後から追加されたため、Codable は decodeIfPresent で旧データ (3 ボタンのみ) を
/// 受け入れて欠けを .none で補う。
struct Mode: Identifiable, Hashable {
    var id: UUID
    var name: String
    var button1: FootswitchAction
    var button2: FootswitchAction
    var button3: FootswitchAction
    var button4: FootswitchAction
    var button5: FootswitchAction
    var button6: FootswitchAction

    init(id: UUID = UUID(), name: String,
         button1: FootswitchAction = .none,
         button2: FootswitchAction = .none,
         button3: FootswitchAction = .none,
         button4: FootswitchAction = .none,
         button5: FootswitchAction = .none,
         button6: FootswitchAction = .none) {
        self.id = id
        self.name = name
        self.button1 = button1
        self.button2 = button2
        self.button3 = button3
        self.button4 = button4
        self.button5 = button5
        self.button6 = button6
    }

    static func makeEmpty(name: String) -> Mode {
        Mode(name: name)
    }

    func action(for button: FootswitchButton) -> FootswitchAction {
        switch button {
        case .button1: return button1
        case .button2: return button2
        case .button3: return button3
        case .button4: return button4
        case .button5: return button5
        case .button6: return button6
        }
    }

    mutating func setAction(_ action: FootswitchAction, for button: FootswitchButton) {
        switch button {
        case .button1: button1 = action
        case .button2: button2 = action
        case .button3: button3 = action
        case .button4: button4 = action
        case .button5: button5 = action
        case .button6: button6 = action
        }
    }
}

// MARK: - Codable (button4〜6 欠落データ後方互換)
extension Mode: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, button1, button2, button3, button4, button5, button6
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.button1 = try c.decode(FootswitchAction.self, forKey: .button1)
        self.button2 = try c.decode(FootswitchAction.self, forKey: .button2)
        self.button3 = try c.decode(FootswitchAction.self, forKey: .button3)
        // 4〜6 は旧データに無いので .none をデフォルト。
        self.button4 = try c.decodeIfPresent(FootswitchAction.self, forKey: .button4) ?? .none
        self.button5 = try c.decodeIfPresent(FootswitchAction.self, forKey: .button5) ?? .none
        self.button6 = try c.decodeIfPresent(FootswitchAction.self, forKey: .button6) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(button1, forKey: .button1)
        try c.encode(button2, forKey: .button2)
        try c.encode(button3, forKey: .button3)
        try c.encode(button4, forKey: .button4)
        try c.encode(button5, forKey: .button5)
        try c.encode(button6, forKey: .button6)
    }
}
