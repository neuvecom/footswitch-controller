import Foundation
import Combine

/// 設定の永続化・取得を担当する。
///
/// 保存先: `~/Library/Application Support/<bundleID>/settings.json`
@MainActor
final class SettingsStore: ObservableObject {
    @Published var profiles: [Profile]

    private let fileURL: URL
    private var saveDebounce: AnyCancellable?

    init() {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                               appropriateFor: nil, create: true))
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = dir.appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "com.luckysama.footswitch-controller",
            isDirectory: true
        )
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("settings.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([Profile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            self.profiles = [Profile.makeDefault()]
        }

        // 変更を自動保存 (デバウンス)
        saveDebounce = $profiles
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }
    }

    // MARK: - Lookup

    var defaultProfile: Profile? {
        profiles.first(where: { $0.isDefault })
    }

    func profile(forBundleID bundleID: String?) -> Profile? {
        if let bundleID, let match = profiles.first(where: { $0.bundleID == bundleID }) {
            return match
        }
        return defaultProfile
    }

    // MARK: - Mutation helpers

    func upsert(_ profile: Profile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
    }

    func remove(profileID: UUID) {
        profiles.removeAll { $0.id == profileID && !$0.isDefault }
    }

    /// `bundleID` 用のプロフィールが無ければ新規に追加して返す。
    @discardableResult
    func ensureProfile(forBundleID bundleID: String, displayName: String) -> Profile {
        if let existing = profiles.first(where: { $0.bundleID == bundleID }) {
            return existing
        }
        let newProfile = Profile.make(for: bundleID, displayName: displayName)
        profiles.append(newProfile)
        return newProfile
    }

    /// 指定プロフィールの activeMode を変更する。
    func setActiveMode(_ modeID: UUID, in profileID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        guard profiles[idx].modes.contains(where: { $0.id == modeID }) else { return }
        profiles[idx].activeModeID = modeID
    }

    // MARK: - Persistence

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("[Footswitch] settings save error: %@", String(describing: error))
        }
    }

    var fileURLForDisplay: URL { fileURL }
}
