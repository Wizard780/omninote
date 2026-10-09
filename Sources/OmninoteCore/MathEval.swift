import Foundation

public enum MathError: Error, Equatable { case syntax(String), unknownName(String) }

/// Small recursive-descent evaluator: + - * / x × ÷ ^ ( ) % ! sqrt/√ log log2 ln ceil floor round abs pi e,
/// "15%" as a percent literal ("100 + 15%" = 115, "50% of 200" = 100) and variables whose names may contain spaces.
public struct MathEval {
    public var variables: [String: Double]

    public init(variables: [String: Double] = [:]) { self.variables = variables }

    public func evaluate(_ source: String) throws -> Double {
        var p = Parser(text: substituteVariables(source))
        let v = try p.expression()
        p.skipSpaces()
        guard p.atEnd else { throw MathError.syntax("unexpected '\(p.rest)'") }
        return v.number
    }

    // Longest names first so "guests" cannot shadow "number of guests".
    private func substituteVariables(_ s: String) -> String {
        var out = s
        for name in variables.keys.sorted(by: { $0.count > $1.count }) {
            guard let value = variables[name] else { continue }
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
            out = out.replacingOccurrences(of: pattern, with: "(\(value))", options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

    private struct Value {
        var number: Double
        var isPercent = false
    }

    private struct Parser {
        let chars: [Character]
        var i = 0
        init(text: String) { chars = Array(text) }

        var atEnd: Bool { i >= chars.count }
        var rest: String { String(chars[i...]) }
        var peek: Character? { atEnd ? nil : chars[i] }

        mutating func skipSpaces() { while let c = peek, c.isWhitespace { i += 1 } }

        mutating func take(_ c: Character) -> Bool {
            skipSpaces()
            if peek == c { i += 1; return true }
            return false
        }

        mutating func takeWord(_ w: String) -> Bool {
            skipSpaces()
            let end = i + w.count
            guard end <= chars.count, String(chars[i..<end]).lowercased() == w else { return false }
            if end < chars.count, chars[end].isLetter { return false }
            i = end
            return true
        }

        mutating func expression() throws -> Value {
            var lhs = try term()
            while true {
                if take("+") { lhs = apply(lhs, try term(), +) }
                else if take("-") || take("−") { lhs = apply(lhs, try term(), -) }
                else { return lhs }
            }
        }

        // "100 + 15%" means 100 + 15% of 100.
        private func apply(_ l: Value, _ r: Value, _ op: (Double, Double) -> Double) -> Value {
            r.isPercent ? Value(number: op(l.number, l.number * r.number)) : Value(number: op(l.number, r.number))
        }

        mutating func term() throws -> Value {
            var lhs = try power()
            while true {
                skipSpaces()
                if take("*") || take("×") || takeWord("x") || takeWord("of") { lhs = Value(number: lhs.number * (try power()).number) }
                else if take("/") || take("÷") { lhs = Value(number: lhs.number / (try power()).number) }
                else if let c = peek, c == "(" || c.isNumber || c == "√" {  // implicit multiplication: 2(3+4), 2√9
                    lhs = Value(number: lhs.number * (try power()).number)
                } else { return lhs }
            }
        }

        mutating func power() throws -> Value {
            let base = try unary()
            skipSpaces()
            if take("^") { return Value(number: pow(base.number, try power().number)) }
            if peek == "*", i + 1 < chars.count, chars[i + 1] == "*" { i += 2; return Value(number: pow(base.number, try power().number)) }
            return base
        }

        mutating func unary() throws -> Value {
            if take("-") || take("−") { let v = try unary(); return Value(number: -v.number, isPercent: v.isPercent) }
            if take("+") { return try unary() }
            if take("√") { return Value(number: (try unary()).number.squareRoot()) }
            if take("∛") { return Value(number: cbrt((try unary()).number)) }
            return try postfix()
        }

        mutating func postfix() throws -> Value {
            var v = try primary()
            while true {
                if take("%") { v = Value(number: v.number / 100, isPercent: true) }
                else if take("!") {
                    if take("!") { v = Value(number: doubleFactorial(v.number)) } else { v = Value(number: tgamma(v.number + 1)) }
                } else { return v }
            }
        }

        private func doubleFactorial(_ n: Double) -> Double {
            var r = 1.0, k = n
            while k > 1 { r *= k; k -= 2 }
            return r
        }

        mutating func primary() throws -> Value {
            skipSpaces()
            guard let c = peek else { throw MathError.syntax("unexpected end") }
            if take("(") {
                let v = try expression()
                guard take(")") else { throw MathError.syntax("missing ')'") }
                return v
            }
            if c.isNumber || c == "." { return Value(number: try number()) }
            if c.isLetter || c == "_" {
                let name = identifier()
                if take("(") {
                    let arg = try expression()
                    guard take(")") else { throw MathError.syntax("missing ')'") }
                    return Value(number: try call(name, arg.number))
                }
                switch name.lowercased() {
                case "pi", "π": return Value(number: .pi)
                case "e": return Value(number: M_E)
                default: throw MathError.unknownName(name)
                }
            }
            throw MathError.syntax("unexpected '\(c)'")
        }

        private func call(_ name: String, _ x: Double) throws -> Double {
            switch name.lowercased() {
            case "sqrt": return x.squareRoot()
            case "cbrt": return cbrt(x)
            case "log": return log10(x)
            case "log2": return log2(x)
            case "ln": return log(x)
            case "ceil": return ceil(x)
            case "floor": return floor(x)
            case "round": return x.rounded()
            case "abs": return abs(x)
            case "sin": return sin(x)
            case "cos": return cos(x)
            case "tan": return tan(x)
            default: throw MathError.unknownName(name)
            }
        }

        mutating func identifier() -> String {
            var s = ""
            while let c = peek, c.isLetter || c.isNumber || c == "_" { s.append(c); i += 1 }
            return s
        }

        // Accepts 1,234.5 and (when no '.' follows a ',') European 1.234,5.
        mutating func number() throws -> Double {
            var s = ""
            while let c = peek, c.isNumber || c == "." || c == "," { s.append(c); i += 1 }
            if s.contains(","), !s.contains(".") || s.lastIndex(of: ",")! > s.lastIndex(of: ".")! {
                s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
            } else {
                s = s.replacingOccurrences(of: ",", with: "")
            }
            guard let d = Double(s) else { throw MathError.syntax("bad number '\(s)'") }
            return d
        }
    }
}

public enum NumberFormat {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        f.usesGroupingSeparator = true
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func string(_ v: Double) -> String {
        if v.isNaN || v.isInfinite { return "?" }
        return formatter.string(from: NSNumber(value: v)) ?? String(v)
    }
}
