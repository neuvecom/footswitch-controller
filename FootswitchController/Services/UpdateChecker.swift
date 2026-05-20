import Foundation
import OSLog

private let logger = Logger(subsystem: "com.luckysama.footswitch-controller", category: "update")

/// GitHub Releases の最新版をチェックする軽量アップデート確認。
/// 自動ダウンロードはせず、新バージョンがあればリリースページへ誘導する。
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var latestVersion: String?
    @Published private(set) var updateAvailable = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var releaseURL: URL?

    private let repo = "neuvecom/footswitch-controller"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false; lastCheckedAt = Date() }

        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                logger.error("update check HTTP error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = Self.normalize(release.tagName)
            self.latestVersion = latest
            self.releaseURL = release.htmlURL
            self.updateAvailable = Self.isNewer(latest, than: Self.normalize(currentVersion))
            logger.info("update check: latest=\(latest, privacy: .public) current=\(self.currentVersion, privacy: .public) available=\(self.updateAvailable, privacy: .public)")
        } catch {
            logger.error("update check failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// "v0.1.0" → "0.1.0"
    private static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// セマンティックバージョンの比較。a > b なら true。
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
