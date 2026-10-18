import AppKit
import SwiftUI
import TallyEngine

/// A colour scheme for the whole window: editor, syntax, results, sidebar and bars.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    /// nil follows the system light/dark setting.
    let isDark: Bool?
    let background: NSColor
    let sidebar: NSColor
    let text: NSColor
    let secondary: NSColor
    let result: NSColor
    let unit: NSColor
    let keyword: NSColor
    let variable: NSColor
    let function: NSColor
    let comment: NSColor
    let date: NSColor
    let header: NSColor
    let selection: NSColor

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id }

    var appearance: NSAppearance? {
        isDark.map { NSAppearance(named: $0 ? .darkAqua : .aqua)! }
    }

    func color(_ style: TokenStyle) -> NSColor {
        switch style {
        case .number: return text
        case .unit: return unit
        case .keyword, .op, .label: return keyword
        case .variable: return variable
        case .function: return function
        case .comment: return comment
        case .header: return header
        case .date: return date
        }
    }

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }

    // MARK: - Catalogue

    private static func hex(_ s: String) -> NSColor {
        var v: UInt64 = 0
        Scanner(string: s.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private static func make(_ id: String, _ name: String, dark: Bool, _ c: [String]) -> Theme {
        // Order: background, sidebar, text, secondary, result, unit, keyword, variable, function, comment, date, header, selection
        let h = c.map(hex)
        return Theme(id: id, name: name, isDark: dark, background: h[0], sidebar: h[1], text: h[2], secondary: h[3],
                     result: h[4], unit: h[5], keyword: h[6], variable: h[7], function: h[8], comment: h[9],
                     date: h[10], header: h[11], selection: h[12])
    }

    private static func adaptive(_ light: String, _ dark: String) -> NSColor {
        let l = hex(light), d = hex(dark)
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l }
    }

    static let system = Theme(
        id: "system", name: "System", isDark: nil,
        background: .textBackgroundColor, sidebar: .windowBackgroundColor, text: .labelColor,
        secondary: .secondaryLabelColor, result: adaptive("#1A8F54", "#73D99E"), unit: .systemTeal,
        keyword: .secondaryLabelColor, variable: .systemOrange, function: .systemBlue,
        comment: .tertiaryLabelColor, date: .systemPurple, header: .labelColor,
        selection: .selectedTextBackgroundColor)

    static let all: [Theme] = [
        system,
        make("midnight", "Midnight", dark: true,
             ["#1E1F24", "#18191D", "#D7D9DE", "#7D828C", "#6FD39A", "#67C5E8", "#8B90A0", "#F0A35E", "#82AAFF", "#5C6070", "#C792EA", "#FFFFFF", "#33415E"]),
        make("paper", "Paper", dark: false,
             ["#FBF8F1", "#F1ECE0", "#2B2B2B", "#8A847A", "#2F8F5B", "#2A7FA8", "#9A938A", "#C2662D", "#3B6FD8", "#B3AC9F", "#8E4EC6", "#111111", "#E8DFC8"]),
        make("solarized-light", "Solarized Light", dark: false,
             ["#FDF6E3", "#EEE8D5", "#586E75", "#93A1A1", "#859900", "#2AA198", "#93A1A1", "#CB4B16", "#268BD2", "#93A1A1", "#6C71C4", "#073642", "#E6DFC8"]),
        make("solarized-dark", "Solarized Dark", dark: true,
             ["#002B36", "#073642", "#93A1A1", "#586E75", "#859900", "#2AA198", "#657B83", "#CB4B16", "#268BD2", "#586E75", "#6C71C4", "#EEE8D5", "#0B4A5A"]),
        make("nord", "Nord", dark: true,
             ["#2E3440", "#272C36", "#D8DEE9", "#7B88A1", "#A3BE8C", "#88C0D0", "#81A1C1", "#D08770", "#8FBCBB", "#616E88", "#B48EAD", "#ECEFF4", "#434C5E"]),
        make("dracula", "Dracula", dark: true,
             ["#282A36", "#21222C", "#F8F8F2", "#8B8FA8", "#50FA7B", "#8BE9FD", "#FF79C6", "#FFB86C", "#BD93F9", "#6272A4", "#F1FA8C", "#FFFFFF", "#44475A"]),
        make("gruvbox", "Gruvbox", dark: true,
             ["#282828", "#1D2021", "#EBDBB2", "#A89984", "#B8BB26", "#83A598", "#A89984", "#FE8019", "#FABD2F", "#7C6F64", "#D3869B", "#FBF1C7", "#3C3836"]),
        make("tokyo-night", "Tokyo Night", dark: true,
             ["#1A1B26", "#16161E", "#C0CAF5", "#565F89", "#9ECE6A", "#7DCFFF", "#9AA5CE", "#FF9E64", "#7AA2F7", "#565F89", "#BB9AF7", "#FFFFFF", "#283457"]),
        make("mocha", "Catppuccin Mocha", dark: true,
             ["#1E1E2E", "#181825", "#CDD6F4", "#7F849C", "#A6E3A1", "#89DCEB", "#9399B2", "#FAB387", "#89B4FA", "#6C7086", "#CBA6F7", "#F5E0DC", "#313244"]),
        make("latte", "Catppuccin Latte", dark: false,
             ["#EFF1F5", "#E6E9EF", "#4C4F69", "#8C8FA1", "#40A02B", "#04A5E5", "#8C8FA1", "#FE640B", "#1E66F5", "#9CA0B0", "#8839EF", "#11111B", "#CCD0DA"]),
        make("github", "GitHub Light", dark: false,
             ["#FFFFFF", "#F6F8FA", "#24292F", "#6E7781", "#1A7F37", "#0969DA", "#6E7781", "#BC4C00", "#8250DF", "#8C959F", "#CF222E", "#000000", "#DDF4FF"]),
        make("monokai", "Monokai", dark: true,
             ["#272822", "#1E1F1C", "#F8F8F2", "#90908A", "#A6E22E", "#66D9EF", "#F92672", "#FD971F", "#AE81FF", "#75715E", "#E6DB74", "#FFFFFF", "#49483E"]),
        make("rose-pine", "Rosé Pine", dark: true,
             ["#191724", "#1F1D2E", "#E0DEF4", "#908CAA", "#9CCFD8", "#EBBCBA", "#908CAA", "#F6C177", "#C4A7E7", "#6E6A86", "#EB6F92", "#FFFFFF", "#2A283E"]),
    ]
}

extension NSColor {
    var swiftUI: Color { Color(nsColor: self) }
}

/// Typefaces offered in settings: system designs plus every installed font family, monospaced first.
enum FontCatalog {
    static let systemOptions: [(id: String, name: String)] = [
        ("system", "System (SF Pro)"),
        ("system-mono", "System Mono (SF Mono)"),
        ("system-rounded", "System Rounded"),
        ("system-serif", "System Serif (New York)"),
    ]

    static let monospacedFamilies: [String] = families(monospaced: true)
    static let proportionalFamilies: [String] = families(monospaced: false)

    private static func families(monospaced: Bool) -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."), let f = NSFont(name: family, size: 13)
                ?? NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 13) else { return false }
            return f.isFixedPitch == monospaced
        }.sorted()
    }

    static func font(_ id: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        switch id {
        case "system": return .monospacedDigitSystemFont(ofSize: size, weight: weight)
        case "system-mono": return .monospacedSystemFont(ofSize: size, weight: weight)
        case "system-rounded": return design(.rounded)
        case "system-serif": return design(.serif)
        default:
            let w = weight == .bold ? 9 : 5
            return NSFontManager.shared.font(withFamily: id, traits: [], weight: w, size: size)
                ?? NSFont(name: id, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }

    static func displayName(_ id: String) -> String {
        systemOptions.first { $0.id == id }?.name ?? id
    }
}

/// Everything about how the editor looks, gathered from settings.
struct EditorStyle: Equatable {
    var theme: Theme
    var fontID: String
    var fontSize: CGFloat
    var lineSpacing: CGFloat
    var resultFraction: CGFloat
    var highlightLine: Bool
}
