import SwiftUI
import TallyEngine

/// Settings window. Each tab is laid out at its natural height (no scrolling); the window resizes per tab.
struct SettingsView: View {
    let library: Library
    @AppStorage("theme") private var themeID = "system"
    @State private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(library: library)
                .tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            ThemeSettings()
                .tabItem { Label("Themes", systemImage: "paintpalette") }.tag("themes")
            TextSettings()
                .tabItem { Label("Text", systemImage: "textformat") }.tag("text")
            WindowSettings()
                .tabItem { Label("Window", systemImage: "macwindow") }.tag("window")
            FilesSettings(library: library)
                .tabItem { Label("Files", systemImage: "folder") }.tag("files")
            RatesSettings(library: library)
                .tabItem { Label("Rates", systemImage: "arrow.triangle.2.circlepath") }.tag("rates")
        }
        .preferredColorScheme(Theme.named(themeID).isDark.map { $0 ? .dark : .light })
    }
}

// MARK: - Building blocks

/// Page wrapper: fixed width, natural height.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) { content }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 26)
            .frame(width: 540, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A titled, rounded group of rows, like System Settings.
private struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 2)
            }
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
        }
    }
}

private struct Row<Control: View>: View {
    let label: String
    var caption: String?
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 12)
                control
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 38)
            if divider { Divider().padding(.leading, 12) }
        }
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var divider = true
    let format: (Double) -> String

    var body: some View {
        Row(label: label, divider: divider) {
            HStack(spacing: 10) {
                if let step { Slider(value: $value, in: range, step: step).frame(width: 200) }
                else { Slider(value: $value, in: range).frame(width: 200) }
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
            }
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let library: Library
    @AppStorage("decimals") private var decimals = 2
    @AppStorage("grouping") private var grouping = true
    @AppStorage("indianGrouping") private var indianGrouping = false
    @AppStorage("use24Hour") private var use24Hour = false
    @AppStorage("anglesInDegrees") private var anglesInDegrees = false
    @AppStorage("copyMode") private var copyMode = "formatted"

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Numbers") {
                Row(label: "Precision", caption: "Decimal places in results") {
                    Stepper("\(decimals)", value: $decimals, in: 0...10).monospacedDigit()
                }
                Row(label: "Thousands separators") { Toggle("", isOn: $grouping).toggleStyle(.switch).labelsHidden() }
                Row(label: "Digit grouping") {
                    Picker("", selection: $indianGrouping) {
                        Text("1,234,567").tag(false)
                        Text("12,34,567").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170).disabled(!grouping)
                }
                Row(label: "Trigonometry", caption: "For plain numbers like sin(30); 30° always works", divider: false) {
                    Picker("", selection: $anglesInDegrees) {
                        Text("Radians").tag(false)
                        Text("Degrees").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 170)
                }
            }
            SettingsGroup(title: "Dates & times") {
                Row(label: "24-hour clock", divider: false) { Toggle("", isOn: $use24Hour).toggleStyle(.switch).labelsHidden() }
            }
            SettingsGroup(title: "Click to copy") {
                Row(label: "Clicking a result copies", divider: false) {
                    Picker("", selection: $copyMode) {
                        Text("As shown  ($1,234.50)").tag("formatted")
                        Text("Number only  (1234.5)").tag("number")
                    }
                    .labelsHidden().fixedSize()
                }
            }
        }
        .onChange(of: decimals) { library.applySettings() }
        .onChange(of: grouping) { library.applySettings() }
        .onChange(of: indianGrouping) { library.applySettings() }
        .onChange(of: use24Hour) { library.applySettings() }
        .onChange(of: anglesInDegrees) { library.applySettings() }
    }
}

// MARK: - Themes

private struct ThemeSettings: View {
    @AppStorage("theme") private var themeID = "system"
    @AppStorage("fontID") private var fontID = "system"
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Colour scheme", footer: "System follows your Mac's light or dark appearance.") {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(theme: theme, fontID: fontID, selected: theme.id == themeID)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { themeID = theme.id } }
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let fontID: String
    let selected: Bool
    @State private var hover = false

    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                line(Text("5 ").foregroundColor(theme.text.swiftUI) + Text("km").foregroundColor(theme.unit.swiftUI), "3.1 mi")
                line(Text("tip").foregroundColor(theme.variable.swiftUI) + Text(" × 2").foregroundColor(theme.keyword.swiftUI), "30%")
                line(Text("sqrt").foregroundColor(theme.function.swiftUI) + Text(" 9").foregroundColor(theme.text.swiftUI), "3")
                Text("// note").foregroundColor(theme.comment.swiftUI)
            }
            .font(Font(FontCatalog.font(fontID, size: 9)))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.background.swiftUI)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hover ? 0.3 : 0.12),
                                  lineWidth: selected ? 2.5 : 1)
            )
            .scaleEffect(hover && !selected ? 1.03 : 1)
            Text(theme.name).font(.caption).foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }

    private func line(_ input: Text, _ result: String) -> some View {
        HStack(spacing: 2) {
            input
            Spacer(minLength: 2)
            Text(result).foregroundColor(theme.result.swiftUI)
        }
    }
}

// MARK: - Text

private struct TextSettings: View {
    @AppStorage("theme") private var themeID = "system"
    @AppStorage("fontID") private var fontID = "system"
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("lineSpacing") private var lineSpacing = 6.0
    @AppStorage("resultFraction") private var resultFraction = 0.4
    @AppStorage("highlightLine") private var highlightLine = true
    @AppStorage("lineNumbers") private var lineNumbers = true
    @AppStorage("zoom") private var zoom = 1.0

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Typeface") {
                Row(label: "Font") {
                    Picker("", selection: $fontID) {
                        Section("System") {
                            ForEach(FontCatalog.systemOptions, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        Section("Monospaced") {
                            ForEach(FontCatalog.monospacedFamilies, id: \.self) { Text($0).tag($0) }
                        }
                        Section("Other") {
                            ForEach(FontCatalog.proportionalFamilies, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    .labelsHidden().frame(width: 220)
                }
                SliderRow(label: "Size", value: $fontSize, range: 11...30, step: 1) { "\(Int($0)) pt" }
                SliderRow(label: "Line spacing", value: $lineSpacing, range: 0...16, step: 1, divider: false) { "\(Int($0))" }
            }
            FontPreview(fontID: fontID, size: fontSize, spacing: lineSpacing, theme: Theme.named(themeID))
            SettingsGroup(title: "Layout", footer: "Zoom the whole window with ⌘+ and ⌘−; ⌘0 resets it. Current zoom: \(Int(zoom * 100))%.") {
                SliderRow(label: "Results column", value: $resultFraction, range: 0.25...0.6) { "\(Int($0 * 100))%" }
                Row(label: "Show line numbers") {
                    Toggle("", isOn: $lineNumbers).toggleStyle(.switch).labelsHidden()
                }
                Row(label: "Highlight current line", divider: false) {
                    Toggle("", isOn: $highlightLine).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }
}

private struct FontPreview: View {
    let fontID: String
    let size: Double
    let spacing: Double
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            row(Text("Price: ").foregroundColor(theme.keyword.swiftUI) + Text("$6 ").foregroundColor(theme.text.swiftUI)
                + Text("times").foregroundColor(theme.keyword.swiftUI) + Text(" 5").foregroundColor(theme.text.swiftUI), "$30")
            row(Text("20 ").foregroundColor(theme.text.swiftUI) + Text("ml").foregroundColor(theme.unit.swiftUI)
                + Text(" in ").foregroundColor(theme.keyword.swiftUI) + Text("tea spoons").foregroundColor(theme.unit.swiftUI), "4.06 tsp")
        }
        .font(Font(FontCatalog.font(fontID, size: size)))
        .padding(14)
        .background(theme.background.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
        .animation(.snappy(duration: 0.2), value: size)
    }

    private func row(_ t: Text, _ result: String) -> some View {
        HStack {
            t
            Spacer()
            Text(result).foregroundColor(theme.result.swiftUI)
        }
    }
}

// MARK: - Window

private struct WindowSettings: View {
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showTotal") private var showTotal = true
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("layout") private var layout = "tabs"

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Open documents") {
                Row(label: "Show open documents as",
                    caption: layout == "tabs" ? "Tabs across the top, like Sublime Text" : "A list in a sidebar", divider: false) {
                    Picker("", selection: $layout) {
                        Label("Tabs", systemImage: "rectangle.topthird.inset.filled").tag("tabs")
                        Label("Sidebar", systemImage: "sidebar.left").tag("sidebar")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
            }
            SettingsGroup(title: "Window") {
                if layout == "sidebar" {
                    Row(label: "Show file name in title bar") { Toggle("", isOn: $showTitle).toggleStyle(.switch).labelsHidden() }
                    Row(label: "Show sidebar", caption: "⌃⌘S") { Toggle("", isOn: $showSidebar).toggleStyle(.switch).labelsHidden() }
                }
                Row(label: "Show total bar", divider: false) { Toggle("", isOn: $showTotal).toggleStyle(.switch).labelsHidden() }
            }
            SettingsGroup(title: "Behaviour") {
                Row(label: "Keep window on top of other apps", divider: false) {
                    Toggle("", isOn: $alwaysOnTop).toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }
}

// MARK: - Files

private struct FilesSettings: View {
    let library: Library
    @AppStorage("sortMode") private var sortMode = "name"

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Storage",
                  footer: "Each calculation is a plain .txt file in this folder. Put it in iCloud Drive or Dropbox to sync between Macs; edits from other apps appear automatically.") {
                Row(label: "Folder", caption: library.folder.path(percentEncoded: false)) {
                    HStack {
                        Button("Change…") { library.chooseFolder() }
                        Button("Reveal") { library.reveal(nil) }
                    }
                }
                Row(label: "Sort sidebar by", divider: false) {
                    Picker("", selection: $sortMode) {
                        Text("Name").tag("name")
                        Text("Last modified").tag("modified")
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 200)
                }
            }
        }
        .onChange(of: sortMode) { withAnimation(.snappy) { library.reloadList() } }
    }
}

// MARK: - Rates

private struct RatesSettings: View {
    let library: Library
    @AppStorage("rateHours") private var rateHours = 6.0

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Exchange rates",
                  footer: "Fiat rates come from open.er-api.com and crypto from Coinbase's public prices. Both are free with no account or API key, and nothing about your calculations is sent. Offline, Tally uses the last rates it downloaded.") {
                Row(label: "Last updated") {
                    Text(library.ratesUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Built-in (offline)")
                        .foregroundStyle(.secondary)
                }
                Row(label: "Refresh automatically") {
                    Picker("", selection: $rateHours) {
                        Text("Every hour").tag(1.0)
                        Text("Every 6 hours").tag(6.0)
                        Text("Once a day").tag(24.0)
                        Text("Never").tag(0.0)
                    }
                    .labelsHidden().fixedSize()
                }
                Row(label: "Update now", divider: false) {
                    Button("Refresh") { library.refreshRates(force: true) }
                }
            }
        }
    }
}
