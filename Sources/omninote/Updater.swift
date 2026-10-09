import AppKit
import OmninoteCore

/// Checks GitHub Releases for a newer build, downloads the DMG to ~/Downloads and opens it.
/// The only network call the app makes; gated by the "check for updates" setting.
final class Updater {
    struct Release { let version: String; let dmg: URL?; let page: URL }

    static let latestURL = URL(string: "https://api.github.com/repos/Wizard780/omninote/releases/latest")!
    static let interval: TimeInterval = 24 * 3600
    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    private let defaults = UserDefaults.standard

    /// Daily check on launch; silent unless something newer exists.
    func checkIfDue(enabled: Bool) {
        guard enabled, Date().timeIntervalSince(defaults.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast) > Updater.interval else { return }
        check(manual: false)
    }

    func check(manual: Bool, status: ((String) -> Void)? = nil) {
        var request = URLRequest(url: Updater.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async { [self] in
                defaults.set(Date(), forKey: "lastUpdateCheck")
                guard let data, let release = parse(data) else {
                    if manual { status?("Could not reach GitHub" + (error.map { ": \($0.localizedDescription)" } ?? "")) }
                    return
                }
                if Version.isNewer(release.version, than: current) {
                    if manual || defaults.string(forKey: "skippedVersion") != release.version { offer(release) }
                    status?("\(release.version) is available")
                } else {
                    status?("Up to date (\(current))")
                }
            }
        }.resume()
    }

    private func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, let page = (json["html_url"] as? String).flatMap(URL.init) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".dmg") }.flatMap(URL.init)
        return Release(version: tag, dmg: dmg, page: page)
    }

    private func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = "omninote \(release.version.drop { $0 == "v" }) is available"
        alert.informativeText = "You have \(current). The download is a disk image; drag omninote to Applications to replace this copy."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: download(release)
        case .alertThirdButtonReturn: defaults.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    private func download(_ release: Release) {
        guard let dmg = release.dmg else { NSWorkspace.shared.open(release.page); return }
        URLSession.shared.downloadTask(with: dmg) { tmp, _, _ in
            guard let tmp else { DispatchQueue.main.async { NSWorkspace.shared.open(release.page) }; return }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            let dest = downloads.appendingPathComponent("omninote-\(release.version.drop { $0 == "v" }).dmg")
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.moveItem(at: tmp, to: dest) } catch { DispatchQueue.main.async { NSWorkspace.shared.open(release.page) }; return }
            DispatchQueue.main.async { NSWorkspace.shared.open(dest) }
        }.resume()
    }
}
