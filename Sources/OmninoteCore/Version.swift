import Foundation

/// Dotted version comparison for update checks: "v0.10.1" > "0.9". Non-numeric parts count as 0.
public enum Version {
    public static func parts(_ s: String) -> [Int] {
        s.trimmingCharacters(in: .whitespaces).drop { $0 == "v" || $0 == "V" }
            .split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
