import SwiftUI
import TallyEngine

struct SettingsView: View {
    let library: Library
    @AppStorage("theme") private var themeID = "system"

    var body: some View {
        TabView {
            GeneralSettings(library: library)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            WindowSettings()
                .tabItem { Label("Window", systemImage: "macwindow") }
            FilesSettings(library: library)
                .tabItem { Label("Files", systemImage: "folder") }
            RatesSettings(library: library)
                .tabItem { Label("Rates", systemImage: "dollarsign.arrow.circlepath") }
        }
        .frame(width: 560)
        .preferredColorScheme(Theme.named(themeID).isDark.map { $0 ? .dark : .light })
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let library: Library
    @AppStorage("decimals") private var decimals = 2
    @AppStorage("grouping") private var grouping = true
    @AppStorage("use24Hour") private var use24Hour = false
    @AppStorage("anglesInDegrees") private var anglesInDegrees = false
    @AppStorage("copyMode") private var copyMode = "formatted"

    var body: some View {
        Form {
            Section("Numbers") {
                Stepper(value: $decimals, in: 0...10) {
                    LabeledContent("Precision", value: "\(decimals) decimal place\(decimals == 1 ? "" : "s")")
                }
                Toggle("Thousands separators", isOn: $grouping)
                Picker("Trigonometry uses", selection: $anglesInDegrees) {
                    Text("Radians").tag(false)
                    Text("Degrees").tag(true)
                }
                Text("Applies to plain numbers like sin(30). Units such as 30° or 1 rad always work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dates & times") {
                Toggle("24-hour clock", isOn: $use24Hour)
            }
            Section("Click to copy") {
                Picker("Clicking a result copies", selection: $copyMode) {
                    Text("Result as shown ($1,234.50)").tag("formatted")
                    Text("Number only (1234.5)").tag("number")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .frame(height: 430)
        .onChange(of: decimals) { library.applySettings() }
        .onChange(of: grouping) { library.applySettings() }
        .onChange(of: use24Hour) { library.applySettings() }
        .onChange(of: anglesInDegrees) { library.applySettings() }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @AppStorage("theme") private var themeID = "system"
    @AppStorage("fontID") private var fontID = "system"
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("lineSpacing") private var lineSpacing = 6.0
    @AppStorage("resultFraction") private var resultFraction = 0.4
    @AppStorage("highlightLine") private var highlightLine = true

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        Form {
            Section("Colour scheme") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(theme: theme, fontID: fontID, selected: theme.id == themeID)
                            .onTapGesture { themeID = theme.id }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Typeface") {
                Picker("Font", selection: $fontID) {
                    Section("System") {
                        ForEach(FontCatalog.systemOptions, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Section("Monospaced") {
                        ForEach(FontCatalog.monospacedFamilies, id: \.self) { family in
                            Text(family).font(Font(FontCatalog.font(family, size: 13))).tag(family)
                        }
                    }
                    Section("Other installed fonts") {
                        ForEach(FontCatalog.proportionalFamilies, id: \.self) { Text($0).tag($0) }
                    }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $fontSize, in: 11...30, step: 1)
                        Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Line spacing") {
                    HStack {
                        Slider(value: $lineSpacing, in: 0...16, step: 1)
                        Text("\(Int(lineSpacing))").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                FontPreview(fontID: fontID, size: fontSize, theme: Theme.named(themeID))
            }
            Section("Layout") {
                LabeledContent("Results column") {
                    HStack {
                        Slider(value: $resultFraction, in: 0.25...0.6)
                        Text("\(Int(resultFraction * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("Highlight current line", isOn: $highlightLine)
            }
        }
        .formStyle(.grouped)
        .frame(height: 620)
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let fontID: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                line(Text("Rent: ").foregroundColor(theme.keyword.swiftUI) + Text("$1,450").foregroundColor(theme.text.swiftUI), "$1,450")
                line(Text("5 ").foregroundColor(theme.text.swiftUI) + Text("km").foregroundColor(theme.unit.swiftUI)
                     + Text(" in ").foregroundColor(theme.keyword.swiftUI) + Text("mi").foregroundColor(theme.unit.swiftUI), "3.11 mi")
                line(Text("tip").foregroundColor(theme.variable.swiftUI) + Text(" = 15%").foregroundColor(theme.text.swiftUI), "15%")
                Text("// note").foregroundColor(theme.comment.swiftUI)
            }
            .font(Font(FontCatalog.font(fontID, size: 10)))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.background.swiftUI)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1))
            Text(theme.name).font(.caption).foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }

    private func line(_ input: Text, _ result: String) -> some View {
        HStack {
            input
            Spacer(minLength: 4)
            Text(result).foregroundColor(theme.result.swiftUI)
        }
    }
}

private struct FontPreview: View {
    let fontID: String
    let size: Double
    let theme: Theme

    var body: some View {
        HStack {
            (Text("20 ").foregroundColor(theme.text.swiftUI) + Text("ml").foregroundColor(theme.unit.swiftUI)
             + Text(" in ").foregroundColor(theme.keyword.swiftUI) + Text("tea spoons").foregroundColor(theme.unit.swiftUI))
            Spacer()
            Text("4.06 tsp").foregroundColor(theme.result.swiftUI)
        }
        .font(Font(FontCatalog.font(fontID, size: size)))
        .padding(12)
        .background(theme.background.swiftUI)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Window

private struct WindowSettings: View {
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showTotal") private var showTotal = true
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        Form {
            Section("Title bar") {
                Toggle("Show file name in the title bar", isOn: $showTitle)
            }
            Section("Panels") {
                Toggle("Show file sidebar", isOn: $showSidebar)
                Toggle("Show total bar", isOn: $showTotal)
            }
            Section("Behaviour") {
                Toggle("Keep window on top of other apps", isOn: $alwaysOnTop)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}

// MARK: - Files

private struct FilesSettings: View {
    let library: Library
    @AppStorage("sortMode") private var sortMode = "name"

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Folder") {
                    Text(library.folder.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button("Change…") { library.chooseFolder() }
                    Button("Show in Finder") { library.reveal(nil) }
                }
                Text("Every calculation is a plain .txt file in this folder. Put it in iCloud Drive or Dropbox to sync between Macs. Edits made in other apps show up here automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sidebar") {
                Picker("Sort files by", selection: $sortMode) {
                    Text("Name").tag("name")
                    Text("Last modified").tag("modified")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
        .onChange(of: sortMode) { library.reloadList() }
    }
}

// MARK: - Rates

private struct RatesSettings: View {
    let library: Library
    @AppStorage("rateHours") private var rateHours = 6.0

    var body: some View {
        Form {
            Section("Exchange rates") {
                LabeledContent("Last updated") {
                    Text(library.ratesUpdated.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Built-in (offline)")
                        .foregroundStyle(.secondary)
                }
                Picker("Refresh automatically", selection: $rateHours) {
                    Text("Every hour").tag(1.0)
                    Text("Every 6 hours").tag(6.0)
                    Text("Once a day").tag(24.0)
                    Text("Never (manual only)").tag(0.0)
                }
                Button("Refresh now") { library.refreshRates(force: true) }
            }
            Section {
                Text("Fiat rates come from open.er-api.com and crypto rates from Coinbase's public price feed. Both are free and need no account or API key; nothing about your calculations is sent. Without a connection, Tally uses the last rates it downloaded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: 300)
    }
}
