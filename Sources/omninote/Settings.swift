import AppKit
import OmninoteCore
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
    @Published var checkForUpdates: Bool { didSet { defaults.set(checkForUpdates, forKey: "checkForUpdates"); onChange?() } }
    @Published var updateStatus = ""
    @Published var palette: Theme = .default  // the applied theme, so the panel is drawn like the editor

    init() {
        themeName = defaults.string(forKey: "theme") ?? "Knight"
        fontFamily = defaults.string(forKey: "fontFamily") ?? "SF Mono"
        fontSize = defaults.object(forKey: "fontSize") as? Double ?? 14
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        pinOnTop = defaults.bool(forKey: "pinOnTop")
        autoDeleteDays = defaults.integer(forKey: "autoDeleteDays")
        checkForUpdates = defaults.object(forKey: "checkForUpdates") as? Bool ?? true
        if !fontNames.contains(fontFamily) { fontNames.append(fontFamily) }
    }
}

extension Color {
    init(hex: String) {
        let c = parseHexColor(hex) ?? (0.5, 0.5, 0.5, 1)
        self.init(.sRGB, red: c.0, green: c.1, blue: c.2, opacity: c.3)
    }
}

/// Drawn with the editor's own theme and font instead of the system form look.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var openThemesFolder: () -> Void
    var reloadThemes: () -> Void
    var chooseFont: () -> Void
    var checkUpdates: () -> Void

    private var bg: Color { Color(hex: model.palette.background) }
    private var fg: Color { Color(hex: model.palette.typeMain) }
    private var dim: Color { Color(hex: model.palette.typeLight) }
    private var accent: Color { Color(hex: model.palette.accent1Main) }
    private var font: Font {
        switch model.fontFamily {
        case "System": return .system(size: 13)
        case "SF Mono": return .system(size: 13, design: .monospaced)
        default: return .custom(model.fontFamily, size: 13)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("appearance")
            row("theme") {
                Picker("", selection: $model.themeName) { ForEach(model.themeNames, id: \.self) { Text($0) } }
            }
            row("font") {
                Picker("", selection: $model.fontFamily) { ForEach(model.fontNames, id: \.self) { Text($0) } }
            }
            row("text size") {
                HStack(spacing: 6) {
                    small("−") { model.fontSize = max(9, model.fontSize - 1) }
                    Text("\(Int(model.fontSize))").frame(width: 24)
                    small("+") { model.fontSize = min(40, model.fontSize + 1) }
                }
            }
            HStack(spacing: 8) {
                small("themes folder", action: openThemesFolder)
                small("reload themes", action: reloadThemes)
                small("other font…", action: chooseFont)
            }
            .padding(.vertical, 8)

            section("where omninote lives")
            row("show in menu bar") { Toggle("", isOn: $model.showInMenuBar) }
            row("show in dock") { Toggle("", isOn: $model.showInDock) }
            row("keep window on top") { Toggle("", isOn: $model.pinOnTop) }
            if !model.showInMenuBar && !model.showInDock {
                Text("// both off: ⌥A is the only way back in").foregroundStyle(dim).padding(.vertical, 6)
            }

            section("notes")
            row("auto-delete untouched notes") {
                Picker("", selection: $model.autoDeleteDays) {
                    Text("never").tag(0); Text("1 day").tag(1); Text("1 week").tag(7); Text("1 month").tag(30); Text("1 year").tag(365)
                }
            }
            section("updates")
            row("check daily (github releases)") { Toggle("", isOn: $model.checkForUpdates) }
            HStack(spacing: 10) {
                small("check now", action: checkUpdates)
                Text(model.updateStatus).foregroundStyle(dim).lineLimit(1)
            }
            .padding(.vertical, 8)
            Text("// ⌥A shows or hides · ⌘[ ⌘] move between notes").foregroundStyle(dim).padding(.top, 4)
        }
        .font(font)
        .foregroundStyle(fg)
        .tint(accent)
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(18)
        .frame(width: 380, alignment: .leading)
        .background(bg)
    }

    private func section(_ title: String) -> some View {
        Text(title).foregroundStyle(accent).fontWeight(.bold).padding(.top, 12).padding(.bottom, 6)
    }

    private func row<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(label)
            Spacer()
            control().fixedSize()
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) { Rectangle().fill(dim.opacity(0.25)).frame(height: 1) }
    }

    private func small(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fixedSize().padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(dim.opacity(0.18)))
        }
        .buttonStyle(.plain)
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
