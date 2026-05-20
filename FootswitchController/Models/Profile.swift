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
struct Mode: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var button1: FootswitchAction
    var button2: FootswitchAction
    var button3: FootswitchAction

    init(id: UUID = UUID(), name: String,
         button1: FootswitchAction = .none,
         button2: FootswitchAction = .none,
         button3: FootswitchAction = .none) {
        self.id = id
        self.name = name
        self.button1 = button1
        self.button2 = button2
        self.button3 = button3
    }

    static func makeEmpty(name: String) -> Mode {
        Mode(name: name)
    }

    func action(for button: FootswitchButton) -> FootswitchAction {
        switch button {
        case .button1: return button1
        case .button2: return button2
        case .button3: return button3
        }
    }

    mutating func setAction(_ action: FootswitchAction, for button: FootswitchButton) {
        switch button {
        case .button1: button1 = action
        case .button2: button2 = action
        case .button3: button3 = action
        }
    }
}
