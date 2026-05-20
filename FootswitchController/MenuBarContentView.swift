import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var monitor: KeyEventMonitor
    @ObservedObject var appWatcher: AppWatcher
    @ObservedObject var store: SettingsStore
    @ObservedObject var dispatcher: ActionDispatcher
    let openSettings: () -> Void
    let openOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            permissionSection
            Divider()
            activeAppSection
            Divider()
            eventLogSection
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 400)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "keyboard")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Footswitch Controller")
                    .font(.headline)
                Text("PC Sensor FS23")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        let color: Color = monitor.isRunning ? .green : .orange
        let label = monitor.isRunning ? "監視中" : "停止中"
        return HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if monitor.hasAccessibilityPermission {
            Label("アクセシビリティ権限: 許可済み", systemImage: "checkmark.shield.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("セットアップが未完了です", systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("アクセシビリティを1つ許可するだけで使えます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("セットアップを開く") { openOnboarding() }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var activeAppSection: some View {
        let front = appWatcher.current
        let profile = store.profile(forBundleID: front?.bundleID)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                Text(front?.localizedName ?? "(no frontmost)")
                    .font(.caption.bold())
                if let bundleID = front?.bundleID {
                    Text(bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            HStack {
                Text("プロフィール:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(profile?.displayName ?? "—")
                    .font(.caption)
                if let profile {
                    Spacer()
                    Menu {
                        ForEach(profile.modes) { mode in
                            Button {
                                store.setActiveMode(mode.id, in: profile.id)
                            } label: {
                                HStack {
                                    if profile.activeModeID == mode.id {
                                        Image(systemName: "checkmark")
                                    }
                                    Text(mode.name)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("モード: \(profile.activeMode?.name ?? "—")")
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if let dispatch = dispatcher.lastDispatch {
                HStack(spacing: 4) {
                    Image(systemName: dispatch.executed ? "bolt.fill" : "bolt.slash")
                        .foregroundStyle(dispatch.executed ? .yellow : .secondary)
                    Text("\(dispatch.button.rawValue) → \(dispatch.action.displayName)")
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("検知ログ")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("デバッグ: 全キーを記録", isOn: $monitor.debugLogAllKeys)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption2)
            }
            if monitor.events.isEmpty {
                Text(monitor.debugLogAllKeys
                     ? "デバッグモード: 任意のキーまたはフットスイッチを試してください。"
                     : "まだイベントを受け取っていません。フットスイッチを踏んでみてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(monitor.events.prefix(40)) { event in
                            HStack(spacing: 8) {
                                Text(Self.timeFormatter.string(from: event.date))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: true)
                                if let button = event.button {
                                    Text(button.rawValue)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: true)
                                } else {
                                    Text("key=\(event.keyCode) flags=\(event.flagsHex)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: true)
                                }
                                Spacer(minLength: 8)
                                Text(event.frontmostApp)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(minHeight: 18)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("設定…") { openSettings() }
            Spacer()
            Button("終了") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
