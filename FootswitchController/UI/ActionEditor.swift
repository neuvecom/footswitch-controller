import SwiftUI

/// 単一の `FootswitchAction` を編集する小さなフォーム。
struct ActionEditor: View {
    @Binding var action: FootswitchAction
    /// switchMode の選択肢として表示するモード一覧 (同プロフィール内)。
    let availableModes: [Mode]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            kindPicker
            detailEditor
        }
    }

    private var kindPicker: some View {
        Picker("種類", selection: kindBinding) {
            ForEach(ActionKind.allCases) { kind in
                Text(kind.label).tag(kind)
            }
        }
        .pickerStyle(.menu)
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { ActionKind.kind(of: action) },
            set: { newKind in
                action = Self.defaultAction(for: newKind, current: action, modes: availableModes)
            }
        )
    }

    @ViewBuilder
    private var detailEditor: some View {
        switch action {
        case .none:
            Text("このボタンは何もしません。")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .keystroke(let code, let mods):
            keystrokeEditor(code: code, mods: mods)

        case .openURL(let url):
            TextField("https://...", text: Binding(
                get: { url.absoluteString },
                set: { newValue in
                    if let u = URL(string: newValue) { action = .openURL(u) }
                }
            ))
            .textFieldStyle(.roundedBorder)

        case .runShellScript(let script):
            TextEditor(text: Binding(
                get: { script },
                set: { action = .runShellScript($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 80)
            .border(Color.secondary.opacity(0.3))

        case .runAppleScript(let script):
            TextEditor(text: Binding(
                get: { script },
                set: { action = .runAppleScript($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 80)
            .border(Color.secondary.opacity(0.3))

        case .switchMode(let modeID):
            Picker("切替先モード", selection: Binding(
                get: { modeID },
                set: { action = .switchMode($0) }
            )) {
                ForEach(availableModes) { mode in
                    Text(mode.name).tag(mode.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private func keystrokeEditor(code: UInt16, mods: ModifierSet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("キー")
                Picker("", selection: Binding(
                    get: { code },
                    set: { action = .keystroke(keyCode: $0, modifiers: mods) }
                )) {
                    ForEach(KeyCodes.presets, id: \.code) { preset in
                        Text(preset.name).tag(preset.code)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            }
            HStack(spacing: 12) {
                modToggle("⌘", .command, code: code, mods: mods)
                modToggle("⌥", .option,  code: code, mods: mods)
                modToggle("⌃", .control, code: code, mods: mods)
                modToggle("⇧", .shift,   code: code, mods: mods)
            }
            Text("送信例: \(FootswitchAction.keystroke(keyCode: code, modifiers: mods).displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func modToggle(_ label: String, _ flag: ModifierSet, code: UInt16, mods: ModifierSet) -> some View {
        Toggle(label, isOn: Binding(
            get: { mods.contains(flag) },
            set: { isOn in
                var newMods = mods
                if isOn { newMods.insert(flag) } else { newMods.remove(flag) }
                action = .keystroke(keyCode: code, modifiers: newMods)
            }
        ))
        .toggleStyle(.button)
    }

    static func defaultAction(for kind: ActionKind, current: FootswitchAction, modes: [Mode]) -> FootswitchAction {
        switch kind {
        case .none: return .none
        case .keystroke:
            if case .keystroke = current { return current }
            return .keystroke(keyCode: 36, modifiers: []) // Return
        case .openURL:
            if case .openURL = current { return current }
            return .openURL(URL(string: "https://example.com")!)
        case .runShellScript:
            if case .runShellScript = current { return current }
            return .runShellScript("echo hello")
        case .runAppleScript:
            if case .runAppleScript = current { return current }
            return .runAppleScript("display notification \"hello\"")
        case .switchMode:
            if case .switchMode = current { return current }
            return .switchMode(modes.first?.id ?? UUID())
        }
    }
}
