import Foundation

/// Reads Antinote theme JSON unchanged, so community themes (dracula/antinote, etc.) drop straight in.
/// Only the keys omninote draws with are decoded; the rest are ignored.
public struct Theme: Codable, Equatable {
    public var name: String
    public var isDarkTheme: Bool
    public var background: String
    public var typeMain: String
    public var typeLight: String      // dimmed text: comments, status bar
    public var typeSubtle: String     // secondary text: titles, computed results
    public var accent1Main: String    // keyword line, links
    public var accent3Main: String    // checked items, success

    public static let `default` = Theme(name: "Knight", isDarkTheme: true,
                                        background: "#0E0F13", typeMain: "#E6E6E6", typeLight: "#6B6F7B",
                                        typeSubtle: "#9CA3AF", accent1Main: "#7C8CF8", accent3Main: "#50FA7B")

    public static func load(from url: URL) throws -> Theme {
        try JSONDecoder().decode(Theme.self, from: Data(contentsOf: url))
    }

    /// All *.json themes in a folder, sorted by name. Unreadable files are skipped.
    public static func loadAll(in folder: URL) -> [Theme] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? load(from: $0) }.sorted { $0.name < $1.name }
    }
}

/// "#RRGGBB" or "#RRGGBBAA" → (r, g, b, a) in 0...1.
public func parseHexColor(_ hex: String) -> (Double, Double, Double, Double)? {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
    let a = s.count == 8 ? Double(v & 0xFF) / 255 : 1
    let rgb = s.count == 8 ? v >> 8 : v
    return (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255, a)
}
