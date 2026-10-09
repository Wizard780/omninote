import AppKit
import OmninoteCore

extension NSColor {
    convenience init(hex: String, fallback: NSColor = .textColor) {
        guard let c = parseHexColor(hex) else { self.init(cgColor: fallback.cgColor)!; return }
        self.init(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
    }
}

/// The whole UI: a text view, a search field, a one-line status bar, and the note stack it edits.
final class EditorController: NSObject, NSTextViewDelegate, NSSearchFieldDelegate {
    let store: Store
    let textView: NSTextView
    let scrollView: NSScrollView
    let searchField = NSSearchField()
    let statusLabel = NSTextField(labelWithString: "")
    let stack = NSStackView()

    private(set) var notes: [Note] = []
    private(set) var index = 0
    private var dirty = false
    private var saveTimer: Timer?
    private var processing = false
    private var searchHits: [String] = []
    private var theme = Theme.default
    private var fontSize: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "fontSize")).nonZero ?? 14

    private var timerLine = ""
    private var timerSpec: Keywords.TimerSpec?
    private var timerStart = Date()
    private var timerElapsedBeforePause: TimeInterval = 0
    private var timerPaused = false
    private var timerTick: Timer?
    private var timerCommandDebounce: Timer?
    private var lastPhase: String?

    init(store: Store) {
        self.store = store
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        super.init()

        textView.delegate = self
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.linkTextAttributes = [.cursor: NSCursor.pointingHand]  // colors come from style(); checkboxes must not look like URLs
        textView.drawsBackground = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        searchField.placeholderString = "Search notes (⏎ next match, Esc close)"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchEntered)
        searchField.isHidden = true

        statusLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.lineBreakMode = .byTruncatingTail

        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 6, right: 0)
        stack.addArrangedSubview(searchField)
        stack.addArrangedSubview(scrollView)
        stack.addArrangedSubview(statusLabel)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -12),
            statusLabel.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -14),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        reload()
        apply(theme: theme)
    }

    // MARK: notes

    var current: Note? { notes.indices.contains(index) ? notes[index] : nil }

    /// Re-read the stack from disk and show the note at `index` (clamped).
    func reload(showing id: String? = nil) {
        flush()
        notes = (try? store.all()) ?? []
        if notes.isEmpty, let n = try? store.create() { notes = [n] }
        index = notes.firstIndex { $0.id == id } ?? min(index, notes.count - 1)
        show(index)
    }

    func show(_ i: Int) {
        flush()
        guard !notes.isEmpty else { statusLabel.stringValue = "Could not create a note (is the disk writable?)"; return }
        index = max(0, min(i, notes.count - 1))
        processing = true
        textView.string = notes[index].content
        textView.undoManager?.removeAllActions()
        processing = false
        refresh()
        textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
        textView.window?.makeFirstResponder(textView)
    }

    func newNote(content: String = "") {
        flush()
        guard let n = try? store.create(content: content) else { return }
        notes.insert(n, at: 0)
        show(0)
    }

    func deleteCurrent() {
        guard let n = current else { return }
        try? store.delete(id: n.id)
        dirty = false
        notes.remove(at: index)
        reload()
    }

    func promoteCurrent() {
        guard let n = current else { return }
        try? store.promote(id: n.id)
        reload(showing: n.id)
    }

    func append(_ text: String) {
        replaceText(with: textView.string + (textView.string.isEmpty || textView.string.hasSuffix("\n") ? "" : "\n") + text)
        textDidChange(Notification(name: NSText.didChangeNotification))
    }

    /// Write the current buffer to disk now (called on navigation, quit, and 300 ms after typing stops).
    func flush() {
        saveTimer?.invalidate()
        guard dirty, let n = current else { return }
        notes[index].content = textView.string
        try? store.save(id: n.id, content: textView.string)
        dirty = false
    }

    // MARK: editing

    func textDidChange(_ notification: Notification) {
        guard !processing else { return }
        dirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.flush() }
        refresh()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) && !searchField.isHidden { closeSearch(); return true }
        return false
    }

    // Plain text only: pasted rich text would carry foreign fonts and colors.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool { true }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL else { return false }
        if url.scheme == "omninote-check", let line = Int(url.host ?? "") {
            replaceText(with: Keywords.toggleCheckbox(textView.string, line: line))
            dirty = true
            refresh()
            flush()
            return true
        }
        // Note text can arrive from untrusted omninote:// URLs, so never launch file:// or app schemes from a click.
        guard ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    /// Run the keyword processor, write back any rewritten text, restyle, update the status bar.
    private func refresh() {
        let processed = Keywords.process(textView.string)
        if processed.text != textView.string {
            replaceText(with: processed.text)
            dirty = true
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.flush() }
        }
        style()
        let (keyword, argument, title) = Keywords.detect(textView.string)
        // A running timer keeps going while you browse other notes; it stops only when its own note drops the keyword.
        if keyword == .timer { updateTimer(argument: argument, title: title) } else if current?.id == timerNoteId { stopTimer() }
        let position = "\(index + 1)/\(notes.count)"
        let parts = [timerStatus ?? processed.status, title.map { "“\($0)”" }, position].compactMap { $0 }
        statusLabel.stringValue = parts.joined(separator: "  ·  ")
    }

    // Replace only the differing middle so the caret and undo stack survive.
    private func replaceText(with new: String) {
        let old = textView.string
        let oldU = Array(old.utf16), newU = Array(new.utf16)
        var prefix = 0
        while prefix < oldU.count, prefix < newU.count, oldU[prefix] == newU[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < oldU.count - prefix, suffix < newU.count - prefix, oldU[oldU.count - 1 - suffix] == newU[newU.count - 1 - suffix] { suffix += 1 }
        let range = NSRange(location: prefix, length: oldU.count - prefix - suffix)
        let replacement = String(utf16CodeUnits: Array(newU[prefix..<(newU.count - suffix)]), count: newU.count - prefix - suffix)
        let caret = textView.selectedRange().location
        processing = true
        // Going through shouldChangeText/didChangeText registers the edit with the undo manager.
        if textView.shouldChangeText(in: range, replacementString: replacement) {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }
        processing = false
        // Results are appended after the caret ("1+1 =|" → "1+1 = 2"); jump past them so Return starts a new line.
        if caret >= range.location, caret <= range.location + range.length, replacement.hasPrefix(" ") || old.utf16.count == caret {
            textView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        }
    }

    private func style() {
        guard let storage = textView.textStorage else { return }
        let text = textView.string as NSString
        let full = NSRange(location: 0, length: text.length)
        let (keyword, _, _) = Keywords.detect(textView.string)
        let base: NSFont = keyword == .code ? .monospacedSystemFont(ofSize: fontSize, weight: .regular) : .systemFont(ofSize: fontSize)
        let main = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight), subtle = NSColor(hex: theme.typeSubtle)
        let accent = NSColor(hex: theme.accent1Main), done = NSColor(hex: theme.accent3Main)

        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: main], range: full)
        var lineNo = 0
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            defer { lineNo += 1 }
            let line = text.substring(with: lineRange)
            if lineNo == 0, keyword != nil {
                storage.addAttributes([.foregroundColor: accent, .font: NSFont.boldSystemFont(ofSize: self.fontSize)], range: lineRange)
                return
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                storage.addAttribute(.foregroundColor, value: light, range: lineRange); return
            }
            if line.hasPrefix("#") {
                storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: self.fontSize + 2), range: lineRange); return
            }
            if keyword == .math, let eq = line.range(of: " = ") {
                let start = lineRange.location + line.utf16.distance(from: line.startIndex, to: eq.lowerBound)
                storage.addAttribute(.foregroundColor, value: subtle, range: NSRange(location: start, length: lineRange.location + lineRange.length - start))
            }
            if keyword == .list {
                for (token, color) in [(Keywords.unchecked, main), (Keywords.checked, done)] {
                    if let r = line.range(of: token) {
                        let loc = lineRange.location + line.utf16.distance(from: line.startIndex, to: r.lowerBound)
                        let box = NSRange(location: loc, length: 3)
                        storage.addAttributes([.link: URL(string: "omninote-check://\(lineNo)")!, .foregroundColor: color, .cursor: NSCursor.pointingHand], range: box)
                        if token == Keywords.checked {
                            storage.addAttributes([.foregroundColor: light, .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                                  range: NSRange(location: loc + 4, length: lineRange.location + lineRange.length - loc - 4))
                        }
                    }
                }
            }
        }
        if keyword != .code, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            for m in detector.matches(in: textView.string, range: full) where m.url != nil {
                storage.addAttributes([.link: m.url!, .foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue], range: m.range)
            }
        }
        storage.endEditing()
        textView.typingAttributes = [.font: base, .foregroundColor: main]
    }

    // MARK: theme & font

    func apply(theme: Theme) {
        self.theme = theme
        let bg = NSColor(hex: theme.background)
        textView.window?.backgroundColor = bg
        textView.insertionPointColor = NSColor(hex: theme.typeMain)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(hex: theme.accent1Main).withAlphaComponent(0.35)]
        statusLabel.textColor = NSColor(hex: theme.typeLight)
        textView.window?.appearance = NSAppearance(named: theme.isDarkTheme ? .darkAqua : .aqua)
        style()
    }

    func adjustFont(by delta: CGFloat) {
        fontSize = max(9, min(40, fontSize + delta))
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        style()
    }

    // MARK: search

    func openSearch() {
        searchField.isHidden = false
        textView.window?.makeFirstResponder(searchField)
    }

    func closeSearch() {
        searchField.isHidden = true
        searchField.stringValue = ""
        searchHits = []
        textView.window?.makeFirstResponder(textView)
        refresh()
    }

    @objc private func searchEntered() {
        let term = searchField.stringValue
        guard !term.isEmpty else { closeSearch(); return }
        if searchHits.isEmpty || searchHits.first != term { searchHits = [term] + ((try? store.search(term)) ?? []).map(\.id) }
        guard searchHits.count > 1 else { statusLabel.stringValue = "No notes match “\(term)”"; return }
        // Rotate through hits: the first element is the term itself, the rest are note ids.
        let next = searchHits.remove(at: 1); searchHits.append(next)
        if let i = notes.firstIndex(where: { $0.id == next }) {
            show(i)
            textView.window?.makeFirstResponder(searchField)
            statusLabel.stringValue = "\(searchHits.count - 1) notes match  ·  ⏎ next"
        }
    }

    func controlTextDidChange(_ obj: Notification) { searchHits = [] }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { closeSearch(); return true }
        return false
    }

    // MARK: timer

    private var timerNoteId: String?

    private var timerElapsed: TimeInterval {
        timerPaused ? timerElapsedBeforePause : timerElapsedBeforePause + Date().timeIntervalSince(timerStart)
    }

    private var timerStatus: String? {
        guard let spec = timerSpec else { return nil }
        let elapsed = timerElapsed
        let paused = timerPaused ? " (paused)" : ""
        switch spec {
        case .stopwatch: return "⏱ " + Keywords.clock(elapsed) + paused
        case .countdown(let s): return elapsed >= s ? "⏰ Time's up" : "⏳ " + Keywords.clock(s - elapsed) + paused
        case .pomodoro(let w, let r):
            let cycle = elapsed.truncatingRemainder(dividingBy: w + r)
            let n = Int(elapsed / (w + r)) + 1
            return cycle < w ? "🍅 work \(Keywords.clock(w - cycle)) · round \(n)" + paused : "☕ break \(Keywords.clock(w + r - cycle)) · round \(n)" + paused
        default: return nil
        }
    }

    // Debounced, so typing "pause" letter by letter does not fire "p" and then "pause" (which would undo itself).
    private func updateTimer(argument: String, title: String?) {
        let line = argument.lowercased().trimmingCharacters(in: .whitespaces)
        guard line != timerLine else { return }
        timerCommandDebounce?.invalidate()
        timerCommandDebounce = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.applyTimerLine(line) }
    }

    private func applyTimerLine(_ line: String) {
        guard line != timerLine else { return }
        timerLine = line
        switch Keywords.parseTimer(line) {
        case .pause?:
            guard timerSpec != nil else { return }
            if timerPaused { timerStart = Date() } else { timerElapsedBeforePause += Date().timeIntervalSince(timerStart) }
            timerPaused.toggle()
        case .restart?: timerStart = Date(); timerElapsedBeforePause = 0; timerPaused = false; lastPhase = nil
        case .stop?: stopTimer()
        case let spec?:
            timerSpec = spec; timerStart = Date(); timerElapsedBeforePause = 0; timerPaused = false; lastPhase = nil
            timerNoteId = current?.id
            timerTick?.invalidate()
            timerTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        case nil: break
        }
        refresh()
    }

    // Alert whenever the timer enters a new phase: countdown done, or a pomodoro work/break switch.
    private func tick() {
        refresh()
        guard let spec = timerSpec else { return }
        let phase = Keywords.timerPhase(spec, elapsed: timerElapsed)
        defer { lastPhase = phase }
        guard let previous = lastPhase, previous != phase else { return }
        NSSound(named: "Glass")?.play()
        NSApp.activate(ignoringOtherApps: true)
        textView.window?.makeKeyAndOrderFront(nil)
    }

    private func stopTimer() {
        timerTick?.invalidate(); timerTick = nil; timerSpec = nil; timerPaused = false; lastPhase = nil; timerNoteId = nil
        if Keywords.detect(textView.string).keyword != .timer { timerLine = "" }
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self == 0 ? nil : self }
}
