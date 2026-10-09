import AppKit
import OmninoteCore
import UniformTypeIdentifiers

@main
enum Main {
    static let delegate = AppDelegate()  // kept alive for the process lifetime
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("omninote")
    static let themesDir = supportDir.appendingPathComponent("Themes")

    var window: NSWindow!
    var editor: EditorController!
    var hotKey: HotKey?
    var statusItem: NSStatusItem?
    var themes: [Theme] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: AppDelegate.themesDir, withIntermediateDirectories: true)
        let store: Store
        do { store = try Store(path: AppDelegate.supportDir.appendingPathComponent("notes.sqlite3").path) } catch {
            NSAlert(error: error).runModal(); NSApp.terminate(nil); return
        }
        let days = UserDefaults.standard.integer(forKey: "autoDeleteDays")
        if days > 0 { try? store.deleteUnmodified(before: Date(timeIntervalSinceNow: -Double(days) * 86400)) }

        editor = EditorController(store: store)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "omninote"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 260, height: 200)
        window.contentView = editor.stack
        window.setFrameAutosaveName("main")
        if !window.setFrameUsingName("main") { window.center() }
        buildMenu()
        loadThemes()
        hotKey = HotKey { [weak self] in self?.toggleVisibility() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "omninote")
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(toggleVisibility)
        for i in NSApp.mainMenu!.item(withTitle: "Notes")!.submenu!.item(withTitle: "Font")!.submenu!.items { i.state = i.title == editor.fontFamily ? .on : .off }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(editor.textView)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }

    func applicationWillTerminate(_ notification: Notification) { editor?.flush() }

    // omninote://createNote?content=…  omninote://appendToCurrent?content=…
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let content = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "content" }?.value ?? ""
            switch url.host ?? url.lastPathComponent {
            case "createNote": editor.newNote(content: content)
            case "appendToCurrent": editor.append(content)
            case "nextNote": editor.swipe(left: true)
            case "previousNote": editor.swipe(left: false)
            default: continue
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func toggleVisibility() {
        if NSApp.isActive, window.isVisible { NSApp.hide(nil) } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(editor.textView)
        }
    }

    // MARK: menu

    private func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        return i
    }

    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About omninote", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        let themeMenu = NSMenu(title: "Theme"); let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: ""); themeItem.submenu = themeMenu
        appMenu.addItem(themeItem)
        let autoMenu = NSMenu(title: "Auto-delete unmodified notes after")
        for (title, days) in [("Never", 0), ("1 day", 1), ("1 week", 7), ("1 month", 30), ("1 year", 365)] {
            let i = NSMenuItem(title: title, action: #selector(setAutoDelete(_:)), keyEquivalent: ""); i.tag = days; autoMenu.addItem(i)
        }
        let autoItem = NSMenuItem(title: "Auto-delete unmodified notes after", action: nil, keyEquivalent: ""); autoItem.submenu = autoMenu
        appMenu.addItem(autoItem)
        appMenu.addItem(withTitle: "Open Themes Folder", action: #selector(openThemesFolder), keyEquivalent: "")
        appMenu.addItem(withTitle: "Reload Themes", action: #selector(loadThemes), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(item("Hide omninote", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Quit omninote", #selector(NSApplication.terminate(_:)), "q"))
        main.addItem(withTitle: "omninote", action: nil, keyEquivalent: "").submenu = appMenu

        let file = NSMenu(title: "File")
        file.addItem(item("New Note", #selector(newNote), "n"))
        file.addItem(item("Delete Note", #selector(deleteNote), "d"))
        file.addItem(.separator())
        file.addItem(item("Export Note…", #selector(exportNote), "s"))
        main.addItem(withTitle: "File", action: nil, keyEquivalent: "").submenu = file

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "Z"))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSTextView.pasteAsPlainText(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        edit.addItem(item("Find Notes…", #selector(find), "f"))
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let notes = NSMenu(title: "Notes")
        notes.addItem(item("Previous Note", #selector(previousNote), "["))
        notes.addItem(item("Next Note", #selector(nextNote), "]"))
        notes.addItem(item("Jump to Front", #selector(jumpToFront), "1"))
        notes.addItem(item("Promote Note to Front", #selector(promote), "1", [.command, .shift]))
        notes.addItem(.separator())
        notes.addItem(item("Pin Window on Top", #selector(togglePin), "p"))
        notes.addItem(item("Show/Hide omninote", #selector(toggleVisibility), "a", .option))
        notes.addItem(.separator())
        notes.addItem(item("Bigger Text", #selector(biggerText), "+"))
        notes.addItem(item("Smaller Text", #selector(smallerText), "-"))
        let fontMenu = NSMenu(title: "Font")
        for name in ["SF Mono", "System", "Menlo", "Courier New", "Other…"] { fontMenu.addItem(withTitle: name, action: #selector(pickFont(_:)), keyEquivalent: "") }
        let fontItem = NSMenuItem(title: "Font", action: nil, keyEquivalent: ""); fontItem.submenu = fontMenu
        notes.addItem(fontItem)
        main.addItem(withTitle: "Notes", action: nil, keyEquivalent: "").submenu = notes

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"))
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {}

    @objc func newNote() { editor.newNote() }
    @objc func deleteNote() { editor.deleteCurrent() }
    @objc func previousNote() { editor.show(editor.index + 1, direction: -1) }   // older notes have higher indices
    @objc func nextNote() { editor.show(editor.index - 1, direction: 1) }
    @objc func jumpToFront() { editor.show(0) }
    @objc func promote() { editor.promoteCurrent() }
    @objc func find() { editor.openSearch() }
    @objc func biggerText() { editor.adjustFont(by: 1) }
    @objc func smallerText() { editor.adjustFont(by: -1) }
    @objc func pickFont(_ sender: NSMenuItem) {
        if sender.title == "Other…" {
            NSFontManager.shared.target = self
            NSFontPanel.shared.setPanelFont(NSFont(name: editor.fontFamily, size: 14) ?? .monospacedSystemFont(ofSize: 14, weight: .regular), isMultiple: false)
            NSFontPanel.shared.orderFront(nil)
            return
        }
        editor.fontFamily = sender.title
        for i in sender.menu!.items { i.state = i == sender ? .on : .off }
    }

    @objc func changeFont(_ sender: Any?) {
        let font = NSFontManager.shared.convert(.systemFont(ofSize: 14))
        editor.fontFamily = font.familyName ?? font.fontName
    }

    @objc func togglePin() { window.level = window.level == .floating ? .normal : .floating }
    @objc func openThemesFolder() { NSWorkspace.shared.open(AppDelegate.themesDir) }

    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "omninote", .credits: NSAttributedString(string: "An open scratchpad. Type a keyword on the first line: math, sum, avg, count, list, timer, code.")])
    }

    @objc func setAutoDelete(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.tag, forKey: "autoDeleteDays")
        for i in sender.menu!.items { i.state = i == sender ? .on : .off }
    }

    @objc func exportNote() {
        guard let note = editor.current else { return }
        editor.flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "md") ?? .plainText]
        let firstLine = note.content.split(separator: "\n").first.map(String.init) ?? "note"
        panel.nameFieldStringValue = firstLine.replacingOccurrences(of: "/", with: "-").prefix(60) + ".txt"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let text = self?.editor.textView.string else { return }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    @objc func loadThemes() {
        var found: [Theme] = []
        if let bundled = Bundle.main.resourceURL { found += Theme.loadAll(in: bundled) }
        found += Theme.loadAll(in: AppDelegate.themesDir)
        themes = found.isEmpty ? [.default] : found
        let menu = NSApp.mainMenu!.items[0].submenu!.items.first { $0.title == "Theme" }!.submenu!
        menu.removeAllItems()
        let selected = UserDefaults.standard.string(forKey: "theme") ?? Theme.default.name
        for (i, t) in themes.enumerated() {
            let item = NSMenuItem(title: t.name, action: #selector(pickTheme(_:)), keyEquivalent: ""); item.tag = i
            item.state = t.name == selected ? .on : .off
            menu.addItem(item)
        }
        editor.apply(theme: themes.first { $0.name == selected } ?? themes[0])
        let days = UserDefaults.standard.integer(forKey: "autoDeleteDays")
        for i in NSApp.mainMenu!.items[0].submenu!.items.first(where: { $0.title.hasPrefix("Auto-delete") })!.submenu!.items { i.state = i.tag == days ? .on : .off }
    }

    @objc func pickTheme(_ sender: NSMenuItem) {
        for i in sender.menu!.items { i.state = i == sender ? .on : .off }
        UserDefaults.standard.set(themes[sender.tag].name, forKey: "theme")
        editor.apply(theme: themes[sender.tag])
    }
}
