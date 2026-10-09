import AppKit
import SwiftUI

/// Everything the settings panel can change. Each property persists itself and calls `onChange`,
/// which the app delegate uses to apply the new value live.
final class SettingsModel: ObservableObject {
    private let defaults = UserDefaults.standard
    var onChange: (() -> Void)?
    var themeNames: [String] = []
    var fontNames = ["SF Mono", "System", "Menlo", "Courier New"]

    @Published var themeName: String { didSet { defaults.set(themeName, forKey: "theme"); onChange?() } }
    @Published var fontFamily: String { didSet { defaults.set(fontFamily, forKey: "fontFamily"); onChange?() } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize"); onChange?() } }
    @Published var showInMenuBar: Bool { didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar"); onChange?() } }
    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock"); onChange?() } }
    @Published var pinOnTop: Bool { didSet { defaults.set(pinOnTop, forKey: "pinOnTop"); onChange?() } }
    @Published var autoDeleteDays: Int { didSet { defaults.set(autoDeleteDays, forKey: "autoDeleteDays"); onChange?() } }

    init() {
        themeName = defaults.string(forKey: "theme") ?? "Knight"
        fontFamily = defaults.string(forKey: "fontFamily") ?? "SF Mono"
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 14
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        pinOnTop = defaults.bool(forKey: "pinOnTop")
        autoDeleteDays = defaults.integer(forKey: "autoDeleteDays")
        if !fontNames.contains(fontFamily) { fontNames.append(fontFamily) }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var openThemesFolder: () -> Void
    var reloadThemes: () -> Void
    var chooseFont: () -> Void

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.themeName) {
                    ForEach(model.themeNames, id: \.self) { Text($0) }
                }
                HStack {
                    Button("Open Themes Folder", action: openThemesFolder)
                    Button("Reload", action: reloadThemes)
                }
                .controlSize(.small)
                Picker("Font", selection: $model.fontFamily) {
                    ForEach(model.fontNames, id: \.self) { Text($0) }
                }
                Button("Other font…", action: chooseFont).controlSize(.small)
                Stepper("Text size: \(Int(model.fontSize))", value: $model.fontSize, in: 9...40)
            }
            Section("Where omninote lives") {
                Toggle("Show in menu bar", isOn: $model.showInMenuBar)
                Toggle("Show in Dock", isOn: $model.showInDock)
                Toggle("Keep window on top", isOn: $model.pinOnTop)
                if !model.showInMenuBar && !model.showInDock {
                    Text("With both off, ⌥A is the only way to bring omninote back.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Notes") {
                Picker("Auto-delete untouched notes after", selection: $model.autoDeleteDays) {
                    Text("Never").tag(0); Text("1 day").tag(1); Text("1 week").tag(7); Text("1 month").tag(30); Text("1 year").tag(365)
                }
                Text("Applied at launch. Global hotkey: ⌥A.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 420)
    }
}

/// A gear button that is invisible until the pointer reaches the window's top-right corner.
final class HoverCornerButton: NSView {
    let button = NSButton()
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")
        button.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        button.isBordered = false
        button.target = self
        button.action = #selector(clicked)
        button.toolTip = "Settings"
        button.alphaValue = 0
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 10),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { fade(to: 1) }
    override func mouseExited(with event: NSEvent) { fade(to: 0) }

    private func fade(to alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.15; button.animator().alphaValue = alpha }
    }

    @objc private func clicked() { onClick?() }

    // Only the button itself should take clicks; the rest of the corner stays the editor's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        button.frame.contains(convert(point, from: superview)) ? button : nil
    }
}
