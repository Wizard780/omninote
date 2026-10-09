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
    let pill = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    private var pillTimer: Timer?
    private var justNavigated = false
    var fontFamily: String = UserDefaults.standard.string(forKey: "fontFamily") ?? "SF Mono" { didSet { UserDefaults.standard.set(fontFamily, forKey: "fontFamily"); style() } }

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
        let swipeView = SwipeTextView(frame: .zero)
        textView = swipeView
        scrollView = NSScrollView()
        scrollView.documentView = swipeView
        swipeView.autoresizingMask = [.width]
        swipeView.isVerticallyResizable = true
        swipeView.isHorizontallyResizable = false
        swipeView.textContainer?.widthTracksTextView = true
        swipeView.minSize = .zero
        swipeView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        super.init()
        swipeView.onSwipe = { [weak self] left in self?.swipe(left: left) }

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
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 14
        pill.isHidden = true
        pill.alphaValue = 0
        pill.translatesAutoresizingMaskIntoConstraints = false
        pillLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(pillLabel)
        stack.addSubview(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -12),
            pill.heightAnchor.constraint(equalToConstant: 28),
            pillLabel.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
            pillLabel.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.widthAnchor.constraint(equalTo: pillLabel.widthAnchor, constant: 28),
        ])
        scrollView.wantsLayer = true

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

    func show(_ i: Int, direction: CGFloat = 0) {
        flush()
        guard !notes.isEmpty else { statusLabel.stringValue = "Could not create a note (is the disk writable?)"; return }
        timerCommandDebounce?.invalidate()
        animateSwap(direction: direction) { [self] in
            flush()  // anything typed during the slide still belongs to the note that was showing
            index = max(0, min(i, notes.count - 1))
            processing = true
            textView.string = notes[index].content
            textView.undoManager?.removeAllActions()
            processing = false
            refresh()
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            textView.window?.makeFirstResponder(textView)
        }
    }

    func newNote(content: String = "", direction: CGFloat = 0) {
        flush()
        guard let n = try? store.create(content: content) else { return }
        notes.insert(n, at: 0)
        show(0, direction: direction)
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

    /// Antinote's swipe rules: past the newest note creates one; away from an empty note deletes it.
    func swipe(left: Bool) {
        let target = left ? index - 1 : index + 1
        if let n = current, n.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, notes.count > 1 {
            deleteCurrent()
            showPill("Empty note deleted")
            if left { show(max(0, index - 1), direction: 1) }  // deleteCurrent reloads at the same index (the older neighbour)
            return
        }
        if target < 0 { newNote(direction: 1); return }
        guard target < notes.count else { showPill("Oldest note"); return }
        show(target, direction: left ? 1 : -1)
        justNavigated = true
    }

    func showPill(_ message: String) {
        pillLabel.stringValue = message
        pillLabel.textColor = NSColor(hex: theme.background)
        pill.layer?.backgroundColor = NSColor(hex: theme.typeMain).withAlphaComponent(0.9).cgColor
        pill.isHidden = false
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; self.pill.animator().alphaValue = 1 }
        pillTimer?.invalidate()
        pillTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.25; self?.pill.animator().alphaValue = 0 },
                                                completionHandler: { if self?.pill.alphaValue == 0 { self?.pill.isHidden = true } })
        }
    }

    /// Slide the old note out and the new one in. direction: +1 = towards newer (content moves left), -1 = older, 0 = none.
    private func animateSwap(direction: CGFloat, _ swap: @escaping () -> Void) {
        guard direction != 0, let layer = scrollView.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { swap(); return }
        let dx = 36 * direction
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.11
            ctx.allowsImplicitAnimation = true
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.scrollView.alphaValue = 0
            layer.transform = CATransform3DMakeTranslation(-dx, 0, 0)
        }, completionHandler: {
            swap()
            layer.transform = CATransform3DMakeTranslation(dx, 0, 0)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.allowsImplicitAnimation = true
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.scrollView.alphaValue = 1
                layer.transform = CATransform3DIdentity
            }
        })
    }

    // MARK: editing

    func textDidChange(_ notification: Notification) {
        guard !processing else { return }
        justNavigated = false
        dirty = true
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.flush() }
        refresh()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) && !searchField.isHidden { closeSearch(); return true }
        if justNavigated {
            justNavigated = false
            let toEnd = [#selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveLeft(_:))].contains(selector)
            let toStart = [#selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveRight(_:))].contains(selector)
            if toEnd || toStart {
                textView.setSelectedRange(NSRange(location: toEnd ? textView.string.utf16.count : 0, length: 0))
                return true
            }
        }
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
        if textView.string.contains(where: { $0 == "\r" || $0 == "\u{2028}" || $0 == "\u{2029}" || $0 == "\u{85}" }) {
            replaceText(with: textView.string.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "[\r\u{2028}\u{2029}\u{85}]", with: "\n", options: .regularExpression))
        }
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
        let base = baseFont(size: fontSize, bold: false)
        let main = NSColor(hex: theme.typeMain), light = NSColor(hex: theme.typeLight), subtle = NSColor(hex: theme.typeSubtle)
        let accent = NSColor(hex: theme.accent1Main), done = NSColor(hex: theme.accent3Main)

        storage.beginEditing()
        storage.setAttributes([.font: base, .foregroundColor: main], range: full)
        var lineNo = 0
        text.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            defer { lineNo += 1 }
            let line = text.substring(with: lineRange)
            if lineNo == 0, keyword != nil {
                storage.addAttributes([.foregroundColor: accent, .font: self.baseFont(size: self.fontSize, bold: true)], range: lineRange)
                return
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                storage.addAttribute(.foregroundColor, value: light, range: lineRange); return
            }
            if line.hasPrefix("#") {
                storage.addAttribute(.font, value: self.baseFont(size: self.fontSize + 2, bold: true), range: lineRange); return
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

    private func baseFont(size: CGFloat, bold: Bool) -> NSFont {
        let weight: NSFont.Weight = bold ? .bold : .regular
        switch fontFamily {
        case "System": return .systemFont(ofSize: size, weight: weight)
        case "SF Mono": return .monospacedSystemFont(ofSize: size, weight: weight)
        default:
            let font = NSFont(name: fontFamily, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
            return bold ? NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) : font
        }
    }

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

    func adjustFont(by delta: CGFloat) { setFontSize(fontSize + delta) }

    func setFontSize(_ size: CGFloat) {
        fontSize = max(9, min(40, size))
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
        let noteId = current?.id
        timerCommandDebounce = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            guard let self, self.current?.id == noteId else { return }
            self.applyTimerLine(line)
        }
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
