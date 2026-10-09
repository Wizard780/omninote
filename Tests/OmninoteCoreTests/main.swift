// Plain assert-based tests (no XCTest: Command Line Tools cannot run XCTest bundles). Run with `make test`.
import Foundation

var failures = 0
var checks = 0

func expect<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T, _ label: String = "", file: String = #file, line: Int = #line) {
    checks += 1
    do {
        let a = try actual()
        if a != expected { failures += 1; print("FAIL \(file):\(line) \(label)\n  expected: \(expected)\n  actual:   \(a)") }
    } catch { failures += 1; print("FAIL \(file):\(line) \(label) threw \(error)") }
}

func expectClose(_ actual: @autoclosure () throws -> Double, _ expected: Double, line: Int = #line) {
    checks += 1
    do {
        let a = try actual()
        if abs(a - expected) > 1e-9 { failures += 1; print("FAIL line \(line): expected \(expected), got \(a)") }
    } catch { failures += 1; print("FAIL line \(line): threw \(error)") }
}

func expectThrows<T>(_ f: @autoclosure () throws -> T, line: Int = #line) {
    checks += 1
    if let v = try? f() { failures += 1; print("FAIL line \(line): expected error, got \(v)") }
}

func eval(_ s: String, _ vars: [String: Double] = [:]) throws -> Double { try MathEval(variables: vars).evaluate(s) }

// MARK: MathEval
expect(try eval("1 + 2 * 3"), 7)
expect(try eval("(1 + 2) * 3"), 9)
expect(try eval("10 / 4"), 2.5)
expect(try eval("2 ^ 10"), 1024)
expect(try eval("2 ** 3 ** 2"), 512)
expect(try eval("-3 + 5"), 2)
expect(try eval("3 x 4"), 12)
expect(try eval("8 ÷ 2"), 4)
expect(try eval("2(3 + 4)"), 14)
expect(try eval("sqrt(16)"), 4)
expect(try eval("√16"), 4)
expectClose(try eval("∛8"), 2)
expectClose(try eval("log(1000)"), 3)
expectClose(try eval("log2(8)"), 3)
expect(try eval("ceil(12.256)"), 13)
expect(try eval("floor(12.256)"), 12)
expectClose(try eval("5!"), 120)
expect(try eval("5!!"), 15)
expect(try eval("100 + 15%"), 115)
expect(try eval("200 - 10%"), 180)
expect(try eval("50% of 200"), 100)
expect(try eval("50%"), 0.5)
expect(try eval("1,234.5 + 0.5"), 1235)
expect(try eval("1.000,25 + 0"), 1000.25)
expect(try eval("number of guests + 1", ["number of guests": 9]), 10)
expect(try eval("guests * 2", ["guests": 4, "number of guests": 9]), 8)
expect(try eval("ans + 5", ["ans": 113]), 118)
expectThrows(try eval("foo + 1"))
expectThrows(try eval("1 +"))
expectThrows(try eval("(1 + 2"))
expect(NumberFormat.string(1492.84), "1,492.84")
expect(NumberFormat.string(115), "115")
expect(NumberFormat.string(22.8125), "22.81")
expect(NumberFormat.string(.infinity), "?")

// MARK: Keywords
expect(Keywords.detect("math\n1+1=").keyword, .math)
let list = Keywords.detect("list: Groceries\nmilk")
expect(list.keyword, .list)
expect(list.title, "Groceries")
let t = Keywords.detect("timer 3:30: Tea")
expect(t.keyword, .timer)
expect(t.argument, "3:30")
expect(t.title, "Tea")
expect(Keywords.detect("mathematics are fun").keyword, nil)
expect(Keywords.detect("").keyword, nil)

let math = Keywords.process("math\nnumber of guests : 9\nnumber of guests + 1 =\n100 * 1.13 = 99\nans + 5 =\n// 1 + 1 =\nfoo =\n")
expect(math.text, "math\nnumber of guests : 9\nnumber of guests + 1 = 10\n100 * 1.13 = 113\nans + 5 = 118\n// 1 + 1 =\nfoo = ?\n")
expect(math.status, "1 variable · 1 line could not be calculated")
expect(Keywords.process(math.text).text, math.text, "math is idempotent")

let sumText = "sum\napples 3\nbananas 2.5, pears 1,000\n// skip 99\n"
expect(Keywords.numbers(in: sumText), [3, 2.5, 1000])
expect(Keywords.process(sumText).status, "sum: 1,005.5")
expect(Keywords.process("avg\n1\n2\n3").status, "avg: 2")
expect(Keywords.process("count\none two\n\nthree").status, "2 lines · 3 words · 12 characters")

let listed = Keywords.process("list\nmilk\n  eggs/x\n[x] bread\n\n# heading\n// note")
expect(listed.text, "list\n[ ] milk\n  [x] eggs\n[x] bread\n\n# heading\n// note")
expect(listed.status, "2/3 done")
expect(Keywords.process(listed.text).text, listed.text, "list is idempotent")
expect(Keywords.toggleCheckbox(listed.text, line: 1), "list\n[x] milk\n  [x] eggs\n[x] bread\n\n# heading\n// note")
expect(Keywords.toggleCheckbox(listed.text, line: 3), "list\n[ ] milk\n  [x] eggs\n[ ] bread\n\n# heading\n// note")

expect(Keywords.parseTimer(""), .stopwatch)
expect(Keywords.parseTimer("3.5"), .countdown(seconds: 210))
expect(Keywords.parseTimer("3:30"), .countdown(seconds: 210))
expect(Keywords.parseTimer("5 1"), .pomodoro(work: 300, rest: 60))
expect(Keywords.parseTimer("pomo"), .pomodoro(work: 1500, rest: 300))
expect(Keywords.parseTimer("p"), .pause)
expect(Keywords.parseTimer("0"), .stop)
expect(Keywords.parseTimer("soon"), nil)
expect(Keywords.clock(210), "3:30")
expect(Keywords.clock(3661), "1:01:01")

// MARK: Store
do {
    let path = NSTemporaryDirectory() + "omninote-test-\(UUID().uuidString).sqlite3"
    defer { try? FileManager.default.removeItem(atPath: path) }
    let store = try Store(path: path)
    let a = try store.create(content: "first")
    let b = try store.create(content: "second")
    expect(try store.all().map(\.content), ["second", "first"])
    try store.promote(id: a.id)
    expect(try store.all().map(\.id), [a.id, b.id])
    try store.save(id: b.id, content: "second 100% edited")
    expect(try store.search("100%").map(\.id), [b.id])
    expect(try store.search("nothing").count, 0)
    try store.delete(id: a.id)
    expect(try store.all().count, 1)
    expect(try store.deleteUnmodified(before: Date(timeIntervalSinceNow: -60)), 0)
    expect(try store.deleteUnmodified(before: Date(timeIntervalSinceNow: 60)), 1)
    expect(try Store(path: path).all().count, 0, "persisted after reopen")
} catch { failures += 1; print("FAIL store: \(error)") }

// MARK: Theme
do {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("evidence/theme-sample-dracula.json")
    let theme = try Theme.load(from: url)
    expect(theme.name, "Dracula")
    expect(theme.background, "#282A36")
    expect(theme.isDarkTheme, true)
    expectClose(parseHexColor(theme.accent1Main)?.0 ?? -1, 0xBD / 255.0)
    expect(parseHexColor("red") == nil, true)
} catch { failures += 1; print("FAIL theme: \(error)") }

print(failures == 0 ? "OK: \(checks) checks passed" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
