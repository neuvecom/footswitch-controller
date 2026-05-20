import AppKit
import SwiftUI

/// 初回起動時にアクセシビリティ権限の付与をガイドする。
/// このアプリはキー検知(session tap)もキー送出(CGEvent.post)もアクセシビリティ1つで動く。
struct OnboardingView: View {
    @ObservedObject var monitor: KeyEventMonitor
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            header
            Divider()
            if monitor.hasAccessibilityPermission {
                grantedState
            } else {
                permissionStep
            }
        }
        .padding(28)
        .frame(width: 480)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Footswitch Controller へようこそ")
                .font(.title2.bold())
            Text("PC Sensor FS23 のフットスイッチに、アプリごとのアクションを割り当てます。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var permissionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("セットアップはあと1ステップ", systemImage: "1.circle.fill")
                .font(.headline)

            Text("フットスイッチの入力を読み取り、アプリにキー操作を送るために「アクセシビリティ」の許可が必要です。これ1つだけで動作します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                stepRow(number: "1", text: "下のボタンで「アクセシビリティ」設定を開く")
                stepRow(number: "2", text: "リストの “FootswitchController” を ON にする")
                stepRow(number: "3", text: "このウィンドウに自動で ✓ が表示されたら完了")
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(8)

            HStack {
                Button {
                    monitor.requestPermissionIfNeeded()
                    open("Privacy_Accessibility")
                } label: {
                    Label("アクセシビリティ設定を開く", systemImage: "lock.shield")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("許可待ち…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold().monospacedDigit())
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var grantedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("準備完了！")
                .font(.title3.bold())
            Text("フットスイッチを踏むと、メニューバーの「設定…」で割り当てたアクションが実行されます。まずは設定でアプリごとのアクションを登録してください。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("はじめる") { onFinish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
