import Foundation

/// Antinote-style modes, activated by a keyword on the first line ("math", "list: Groceries", ...).
public enum Keyword: String, CaseIterable {
    case math, sum, avg, count, list, timer, code
}

public struct Processed: Equatable {
    public var text: String        // possibly rewritten note text
    public var status: String?     // one line for the bottom bar
}

public enum Keywords {
    // Possessive quantifiers so "250g" is skipped rather than backtracked into "25".
    private static let numberRegex = try! NSRegularExpression(pattern: #"(?<![\p{L}\p{N}])-?\d++(?:[.,]\d++)*+(?![\p{L}])"#)

    /// First-line detection: "math", "list: Title", "timer 5 1: Laundry".
    public static func detect(_ text: String) -> (keyword: Keyword?, argument: String, title: String?) {
        let first = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let (head, title) = splitTitle(first)
        let words = head.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let w = words.first, let k = Keyword(rawValue: w.lowercased()) else { return (nil, "", nil) }
        // Only "timer" takes arguments; "List of things" or "Count the days" must stay plain notes.
        guard words.count == 1 || k == .timer else { return (nil, "", nil) }
        return (k, words.count > 1 ? String(words[1]).trimmingCharacters(in: .whitespaces) : "", title)
    }

    // The title starts at the first ':' that is not followed by a digit (so "timer 3:30" keeps its time).
    private static func splitTitle(_ line: String) -> (String, String?) {
        let chars = Array(line)
        for (i, c) in chars.enumerated() where c == ":" {
            let next = i + 1 < chars.count ? chars[i + 1] : " "
            if !next.isNumber {
                return (String(chars[..<i]).trimmingCharacters(in: .whitespaces),
                        String(chars[(i + 1)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        return (line.trimmingCharacters(in: .whitespaces), nil)
    }

    public static func process(_ text: String) -> Processed {
        let (keyword, _, _) = detect(text)
        switch keyword {
        case .math: return processMath(text)
        case .sum, .avg, .count: return Processed(text: text, status: aggregate(text, keyword!))
        case .list: return processList(text)
        default: return Processed(text: text, status: nil)
        }
    }

    static func bodyLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }

    // MARK: math

    /// Lines ending in "expr =" get their result appended; "name : expr" assigns a variable; "ans" is the last result.
    public static func processMath(_ text: String) -> Processed {
        var lines = bodyLines(text)
        var eval = MathEval()
        var errors = 0
        for i in lines.indices.dropFirst() {
            let line = lines[i]
            if isComment(line) { continue }
            if let eq = line.firstIndex(of: "="), !line.contains(":") || eq < line.firstIndex(of: ":")! {
                let expr = String(line[..<eq])
                guard expr.trimmingCharacters(in: .whitespaces).isEmpty == false else { continue }
                let result: String
                if let v = try? eval.evaluate(expr) {
                    result = NumberFormat.string(v)
                    eval.variables["ans"] = v
                } else {
                    result = "?"; errors += 1
                }
                lines[i] = expr.trimmingCharacters(in: .whitespaces) + " = " + result
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                guard !name.isEmpty, let v = try? eval.evaluate(String(line[line.index(after: colon)...])) else { continue }
                eval.variables[name] = v
            }
        }
        let vars = eval.variables.filter { $0.key != "ans" }.count
        var parts: [String] = []
        if vars > 0 { parts.append("\(vars) variable\(vars == 1 ? "" : "s")") }
        if errors > 0 { parts.append("\(errors) line\(errors == 1 ? "" : "s") could not be calculated") }
        return Processed(text: lines.joined(separator: "\n"), status: parts.isEmpty ? "math" : parts.joined(separator: " · "))
    }

    // MARK: sum / avg / count

    public static func numbers(in text: String) -> [Double] {
        bodyLines(text).dropFirst().filter { !isComment($0) }.flatMap { line -> [Double] in
            let ns = line as NSString
            return numberRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap {
                Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: ""))
            }
        }
    }

    public static func aggregate(_ text: String, _ k: Keyword) -> String {
        let nums = numbers(in: text)
        switch k {
        case .sum: return "sum: " + NumberFormat.string(nums.reduce(0, +))
        case .avg: return "avg: " + (nums.isEmpty ? "–" : NumberFormat.string(nums.reduce(0, +) / Double(nums.count)))
        default:
            let body = bodyLines(text).dropFirst().filter { !isComment($0) }
            let lines = body.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let words = body.flatMap { $0.split(whereSeparator: { $0.isWhitespace }) }.count
            let chars = body.reduce(0) { $0 + $1.count }
            return "\(lines.count) lines · \(words) words · \(chars) characters"
        }
    }

    // MARK: list

    public static let unchecked = "[ ] "
    public static let checked = "[x] "
    // Complete marker anywhere ("[ ] milk", "[x]done"), or a half-typed one only when it is all there is ("[", "[x").
    private static let markerRegex = try! NSRegularExpression(pattern: #"^\[[ xX]?\]\s*|^\[[ xX]?$"#)

    /// Every non-empty body line becomes a checkbox item; a trailing "/x" toggles the item and is consumed.
    public static func processList(_ text: String) -> Processed {
        var lines = bodyLines(text)
        var done = 0, total = 0
        for i in lines.indices.dropFirst() {
            var line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isComment(line) || trimmed.hasPrefix("#") { continue }
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            var body = String(line.dropFirst(indent.count))
            if body.hasPrefix("- ") { body.removeFirst(2) }
            var isChecked = false
            // A complete or half-typed marker ("[", "[ ", "[]", "[x", "[x] ") is the checkbox, never item text.
            if let m = markerRegex.firstMatch(in: body, range: NSRange(location: 0, length: body.utf16.count)) {
                let marker = (body as NSString).substring(with: m.range)
                isChecked = marker.lowercased().contains("x")
                body = (body as NSString).substring(from: m.range.length)
            }
            if body.hasSuffix("/x"), !body.contains("://") { body.removeLast(2); isChecked.toggle() }  // not a URL path
            line = indent + (isChecked ? checked : unchecked) + body
            lines[i] = line
            total += 1
            if isChecked { done += 1 }
        }
        return Processed(text: lines.joined(separator: "\n"), status: "\(done)/\(total) done")
    }

    /// Toggle the checkbox on the given line (used for click-to-toggle).
    public static func toggleCheckbox(_ text: String, line index: Int) -> String {
        var lines = bodyLines(text)
        guard lines.indices.contains(index) else { return text }
        let l = lines[index]
        if let r = l.range(of: unchecked) { lines[index] = l.replacingCharacters(in: r, with: checked) }
        else if let r = l.range(of: checked) { lines[index] = l.replacingCharacters(in: r, with: unchecked) }
        return lines.joined(separator: "\n")
    }

    // MARK: timer

    public enum TimerSpec: Equatable {
        case stopwatch
        case countdown(seconds: Double)
        case pomodoro(work: Double, rest: Double)
        case pause, restart, stop
    }

    /// "timer" → stopwatch; "timer 3.5" / "timer 3:30" → countdown; "timer 5 1" → pomodoro; "timer pomo" → 25/5;
    /// "timer p|r|s|0" → controls. Returns nil when the argument is not understood.
    public static func parseTimer(_ argument: String) -> TimerSpec? {
        let arg = argument.lowercased().trimmingCharacters(in: .whitespaces)
        switch arg {
        case "": return .stopwatch
        case "p", "pause": return .pause
        case "r", "restart": return .restart
        case "s", "stop", "0": return .stop
        case "pomo", "pomodoro": return .pomodoro(work: 25 * 60, rest: 5 * 60)
        default: break
        }
        let parts = arg.split(separator: " ").map(String.init)
        guard let first = minutes(parts[0]) else { return nil }
        if parts.count == 2, let second = minutes(parts[1]), first + second > 0 { return .pomodoro(work: first, rest: second) }
        return parts.count == 1 && first > 0 ? .countdown(seconds: first) : nil
    }

    private static let maxSeconds = 100 * 86400.0  // Double("inf") and "1e30" parse; keep timers finite and Int-safe

    // "3.5" minutes, or "3:30" min:sec. Returns seconds.
    private static func minutes(_ s: String) -> Double? {
        let seconds: Double?
        if let colon = s.firstIndex(of: ":") {
            guard let m = Double(s[..<colon]), let sec = Double(s[s.index(after: colon)...]) else { return nil }
            seconds = m * 60 + sec
        } else {
            seconds = Double(s).map { $0 * 60 }
        }
        guard let v = seconds, v.isFinite, v >= 0, v <= maxSeconds else { return nil }
        return v
    }

    /// Which phase a running timer is in; the app alerts whenever this changes.
    public static func timerPhase(_ spec: TimerSpec, elapsed: Double) -> String {
        switch spec {
        case .stopwatch: return "run"
        case .countdown(let s): return elapsed >= s ? "done" : "run"
        case .pomodoro(let w, let r):
            let n = Int(elapsed / (w + r))
            return "\(n)-" + (elapsed.truncatingRemainder(dividingBy: w + r) < w ? "work" : "break")
        default: return ""
        }
    }

    public static func clock(_ seconds: Double) -> String {
        let s = seconds.isFinite ? max(0, Int(min(seconds, maxSeconds).rounded())) : 0
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
