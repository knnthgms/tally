import SwiftUI
import TallyEngine

struct ContentView: View {
    @Bindable var library: Library
    @AppStorage("theme") private var themeID = "system"
    @AppStorage("fontID") private var fontID = "system"
    @AppStorage("fontSize") private var fontSize = 15.0
    @AppStorage("lineSpacing") private var lineSpacing = 6.0
    @AppStorage("resultFraction") private var resultFraction = 0.4
    @AppStorage("highlightLine") private var highlightLine = true
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showTotal") private var showTotal = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("zoom") private var zoom = 1.0

    @State private var editing: URL?
    @State private var draft = ""
    @State private var trashing: CalcFile?
    @State private var copiedTotal = false
    @FocusState private var renameFocused: Bool

    private var theme: Theme { Theme.named(themeID) }
    private var z: CGFloat { CGFloat(zoom) }

    private var style: EditorStyle {
        EditorStyle(theme: theme, fontID: fontID, fontSize: fontSize * zoom, lineSpacing: lineSpacing * zoom,
                    resultFraction: resultFraction, highlightLine: highlightLine)
    }

    /// The native split view owns the collapse animation; this just maps it onto the saved setting.
    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(get: { showSidebar ? .all : .detailOnly },
                set: { showSidebar = $0 != .detailOnly })
    }

    var body: some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 150, ideal: 200, max: 340)
        } detail: {
            VStack(spacing: 0) {
                if library.selection != nil {
                    EditorView(library: library, style: style)
                } else {
                    emptyState
                }
                if showTotal { footer }
            }
            .background(theme.background.swiftUI.ignoresSafeArea())
            .toolbar { toolbarContent }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfigurator(theme: theme, alwaysOnTop: alwaysOnTop))
        .preferredColorScheme(theme.isDark.map { $0 ? .dark : .light })
        .confirmationDialog("Move “\(trashing?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let f = trashing { withAnimation(.easeOut(duration: 0.15)) { library.trash(f.url) } }
                trashing = nil
            }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCalculation)) { _ in createFile() }
        .onReceive(NotificationCenter.default.publisher(for: .renameCurrent)) { _ in
            if let url = library.selection { startRename(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reloadList()
            library.reloadIfChangedOnDisk()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if showTitle {
                Text(currentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondary.swiftUI)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: createFile) { Label("New Calculation", systemImage: "square.and.pencil") }
                .help("New calculation (⌘N)")
        }
    }

    private var currentName: String {
        library.files.first { $0.url == library.selection }?.name ?? "Tally"
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2 * z) {
                    ForEach(library.files) { file in
                        row(file).transition(.opacity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 44)
            }
            .scrollIndicators(.never)
            .ignoresSafeArea(.container, edges: .top)
            sidebarFooter
        }
        // System theme keeps the native translucent sidebar; other themes paint their own colour.
        .background { if theme.id != "system" { theme.sidebar.swiftUI.ignoresSafeArea() } }
    }

    @ViewBuilder
    private func row(_ file: CalcFile) -> some View {
        let selected = file.url == library.selection
        Group {
            if editing == file.url {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13 * z, weight: .medium))
                    .foregroundStyle(theme.text.swiftUI)
                    .focused($renameFocused)
                    .onSubmit(commitRename)
                    .onChange(of: renameFocused) { _, focused in if !focused { commitRename() } }
                    .onExitCommand { editing = nil; focusEditor() }
                    .padding(.horizontal, 10 * z)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6 * z).fill(theme.selection.swiftUI))
            } else {
                FileRowLabel(name: file.name, selected: selected, theme: theme, zoom: z)
            }
        }
        .frame(height: 28 * z)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { startRename(file.url) }
        .onTapGesture { if editing != file.url { library.select(file.url) } }
        .contextMenu {
            Button("Rename") { startRename(file.url) }
            Button("Duplicate") { library.duplicate(file.url) }
            Button("Show in Finder") { library.reveal(file.url) }
            Divider()
            Button("Move to Trash…", role: .destructive) { trashing = file }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "folder", color: theme.secondary.swiftUI, zoom: z, help: "Open the Tally folder in Finder") {
                library.reveal(nil)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 13 * z))
                    .foregroundStyle(theme.secondary.swiftUI)
                    .frame(width: 26 * z, height: 24 * z)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 8)
        .frame(height: 34 * z)
    }

    // MARK: Files

    private func createFile() {
        if !showSidebar { showSidebar = true }
        var url: URL?
        withAnimation(.easeOut(duration: 0.15)) { url = library.newFile() }
        if let url { startRename(url) }
    }

    private func startRename(_ url: URL) {
        draft = url.deletingPathExtension().lastPathComponent
        editing = url
        DispatchQueue.main.async { renameFocused = true }
    }

    private func commitRename() {
        guard let url = editing else { return }
        editing = nil
        library.rename(url, to: draft)
        focusEditor()
    }

    private func focusEditor() {
        DispatchQueue.main.async {
            if let tv = library.textView { tv.window?.makeFirstResponder(tv) }
        }
    }

    // MARK: Editor chrome

    private var emptyState: some View {
        VStack(spacing: 10 * z) {
            Image(systemName: "equal.square")
                .font(.system(size: 40 * z, weight: .light))
                .foregroundStyle(theme.secondary.swiftUI.opacity(0.6))
            Text("No calculation open")
                .font(.system(size: 15 * z, weight: .medium))
                .foregroundStyle(theme.text.swiftUI)
            Button("New Calculation", action: createFile)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 8 * z) {
            if let err = library.currentLineError {
                Image(systemName: "exclamationmark.circle").foregroundStyle(theme.variable.swiftUI)
                Text(err).foregroundStyle(theme.secondary.swiftUI).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            if let total = library.total {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(total, forType: .string)
                    copiedTotal = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { copiedTotal = false }
                } label: {
                    HStack(spacing: 6 * z) {
                        Text(copiedTotal ? "Copied" : "Total").foregroundStyle(theme.secondary.swiftUI)
                        Text(total).foregroundStyle(theme.result.swiftUI).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy the total")
            }
        }
        .font(.system(size: 12 * z))
        .padding(.horizontal, 22 * z)
        .frame(height: 30 * z)
        .background(theme.text.swiftUI.opacity(0.03))
        .overlay(alignment: .top) { Rectangle().fill(theme.text.swiftUI.opacity(0.06)).frame(height: 1) }
    }
}

struct FileRowLabel: View {
    let name: String
    let selected: Bool
    let theme: Theme
    let zoom: CGFloat
    @State private var hover = false

    var body: some View {
        Text(name)
            .font(.system(size: 13 * zoom, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? theme.text.swiftUI : theme.text.swiftUI.opacity(0.75))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * zoom)
            .background(
                RoundedRectangle(cornerRadius: 6 * zoom)
                    .fill(selected ? theme.selection.swiftUI : theme.text.swiftUI.opacity(hover ? 0.05 : 0))
            )
            .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let color: Color
    var zoom: CGFloat = 1
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13 * zoom))
                .foregroundStyle(color.opacity(hover ? 1 : 0.8))
                .frame(width: 26 * zoom, height: 24 * zoom)
                .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(hover ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Applies window settings SwiftUI doesn't expose: theme appearance and float-on-top.
struct WindowConfigurator: NSViewRepresentable {
    let theme: Theme
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.titlebarSeparatorStyle = .none
            w.appearance = theme.appearance
            w.backgroundColor = theme.background
            w.level = alwaysOnTop ? .floating : .normal
        }
    }
}

extension Notification.Name {
    static let renameCurrent = Notification.Name("TallyRenameCurrent")
    static let newCalculation = Notification.Name("TallyNewCalculation")
}
