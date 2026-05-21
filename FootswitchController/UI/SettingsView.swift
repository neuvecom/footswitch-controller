import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var appWatcher: AppWatcher

    @State private var selectedProfileID: UUID?
    @State private var selectedModeID: UUID?

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 220)
        } detail: {
            if let profileID = selectedProfileID,
               let idx = store.profiles.firstIndex(where: { $0.id == profileID }) {
                ProfileEditor(
                    profile: $store.profiles[idx],
                    selectedModeID: $selectedModeID
                )
                .padding()
            } else {
                Text("左のリストからプロフィールを選択してください。")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 720, minHeight: 560)
        .onAppear {
            if selectedProfileID == nil { selectedProfileID = store.profiles.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selectedProfileID) {
                Section("プロフィール") {
                    ForEach(store.profiles) { profile in
                        HStack {
                            Image(systemName: profile.isDefault ? "asterisk.circle" : "app.fill")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.displayName)
                                if let bundleID = profile.bundleID {
                                    Text(bundleID)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tag(Optional(profile.id))
                    }
                }
            }
            Divider()
            HStack {
                Button {
                    addProfileForFrontmost()
                } label: {
                    Label("現在のアプリを追加", systemImage: "plus")
                }
                .help(appWatcher.current?.localizedName ?? "frontmost アプリ")
                Spacer()
                Button {
                    if let id = selectedProfileID { store.remove(profileID: id) }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedProfile?.isDefault ?? true)
            }
            .padding(8)
        }
    }

    private var selectedProfile: Profile? {
        guard let id = selectedProfileID else { return nil }
        return store.profiles.first(where: { $0.id == id })
    }

    private func addProfileForFrontmost() {
        guard let front = appWatcher.current,
              let bundleID = front.bundleID else { return }
        let added = store.ensureProfile(forBundleID: bundleID, displayName: front.localizedName)
        selectedProfileID = added.id
    }
}

private struct ProfileEditor: View {
    @Binding var profile: Profile
    @Binding var selectedModeID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            modeBar
            Divider()
            if let modeIdx = selectedModeIndex {
                ModeEditor(
                    mode: $profile.modes[modeIdx],
                    availableModes: profile.modes
                )
            } else {
                Text("モードを選択してください。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .onAppear { syncSelectedMode() }
        .onChange(of: profile.id) { _ in syncSelectedMode() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                TextField("プロフィール名", text: $profile.displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                if let bundleID = profile.bundleID {
                    Text(bundleID).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Default (どのアプリにもマッチ)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var modeBar: some View {
        HStack {
            ForEach(profile.modes) { mode in
                Button {
                    selectedModeID = mode.id
                } label: {
                    HStack(spacing: 4) {
                        if profile.activeModeID == mode.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                        Text(mode.name)
                    }
                }
                .buttonStyle(.bordered)
                .background(selectedModeID == mode.id ? Color.accentColor.opacity(0.15) : .clear)
                .cornerRadius(6)
            }
            Spacer()
            Button {
                let newMode = Mode.makeEmpty(name: "Mode \(profile.modes.count + 1)")
                profile.modes.append(newMode)
                selectedModeID = newMode.id
            } label: { Label("モード追加", systemImage: "plus") }
            Button {
                if let id = selectedModeID, profile.modes.count > 1 {
                    profile.modes.removeAll { $0.id == id }
                    if profile.activeModeID == id {
                        profile.activeModeID = profile.modes.first?.id ?? UUID()
                    }
                    selectedModeID = profile.modes.first?.id
                }
            } label: { Image(systemName: "minus") }
            .disabled(profile.modes.count <= 1)
        }
    }

    private var selectedModeIndex: Int? {
        guard let id = selectedModeID else { return nil }
        return profile.modes.firstIndex(where: { $0.id == id })
    }

    private func syncSelectedMode() {
        if selectedModeID == nil || !profile.modes.contains(where: { $0.id == selectedModeID }) {
            selectedModeID = profile.activeModeID
        }
    }
}

private struct ModeEditor: View {
    @Binding var mode: Mode
    let availableModes: [Mode]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("モード名", text: $mode.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Spacer()
            }
            buttonRow("Button 1 (F13)", binding: $mode.button1)
            Divider()
            buttonRow("Button 2 (Option+F13)", binding: $mode.button2)
            Divider()
            buttonRow("Button 3 (Ctrl+F13)", binding: $mode.button3)
        }
    }

    private func buttonRow(_ title: String, binding: Binding<FootswitchAction>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            ActionEditor(action: binding, availableModes: availableModes)
        }
    }
}
