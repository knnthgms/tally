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
    @AppStorage("sidebarWidth") private var sidebarWidth = 200.0
    @AppStorage("showTitle") private var showTitle = true
    @AppStorage("showTotal") private var showTotal = true
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("zoom") private var zoom = 1.0

    @State private var editing: URL?
    @State private var draft = ""
    @State private var trashing: CalcFile?
    @State private var copiedTotal = false
    @State private var dragStartWidth: Double?
    @FocusState private var renameFocused: Bool
    @Namespace private var selectionNS

    private var theme: Theme { Theme.named(themeID) }
    private var z: CGFloat { CGFloat(zoom) }

    private var style: EditorStyle {
        EditorStyle(theme: theme, fontID: fontID, fontSize: fontSize * zoom, lineSpacing: lineSpacing * zoom,
                    resultFraction: resultFraction, highlightLine: highlightLine)
    }

    private static let sidebarSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth * z)
                .frame(width: showSidebar ? sidebarWidth * z : 0, alignment: .trailing)
                .clipped()
                .overlay(alignment: .trailing) { if showSidebar { resizeHandle } }
            VStack(spacing: 0) {
                if library.selection != nil {
                    EditorView(library: library, style: style)
                        .padding(.top, 38)
                } else {
                    emptyState
                }
                if showTotal { footer.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            .background(theme.background.swiftUI)
        }
        .ignoresSafeArea()
        .background(theme.background.swiftUI)
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfigurator(theme: theme, alwaysOnTop: alwaysOnTop))
        .preferredColorScheme(theme.isDark.map { $0 ? .dark : .light })
        .animation(.snappy(duration: 0.25), value: showTotal)
        .confirmationDialog("Move “\(trashing?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let f = trashing { withAnimation(.snappy) { library.trash(f.url) } }
                trashing = nil
            }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .newCalculation)) { _ in createFile() }
        .onReceive(NotificationCenter.default.publisher(for: .renameCurrent)) { _ in
            if let url = library.selection { startRename(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in toggleSidebar() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reloadList()
            library.reloadIfChangedOnDisk()
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) { Label("Sidebar", systemImage: "sidebar.left") }
                .help("Show or hide the sidebar (⌃⌘S)")
        }
        ToolbarItem(placement: .principal) {
            if showTitle {
                Text(currentName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondary.swiftUI)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: currentName)
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

    private func toggleSidebar() {
        withAnimation(Self.sidebarSpring) { showSidebar.toggle() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44)
            ScrollView {
                VStack(spacing: 2 * z) {
                    ForEach(library.files) { file in
                        row(file)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.95))))
                    }
                }
                .padding(.horizontal, 8)
                .animation(.snappy(duration: 0.28), value: library.files)
                .animation(.snappy(duration: 0.22), value: library.selection)
            }
            .scrollIndicators(.never)
            sidebarFooter
        }
        .background(theme.sidebar.swiftUI)
        .overlay(alignment: .trailing) {
            Rectangle().fill(theme.text.swiftUI.opacity(0.08)).frame(width: 1)
        }
    }

    @ViewBuilder
    private func row(_ file: CalcFile) -> some View {
        let selected = file.url == library.selection
        ZStack(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 6 * z)
                    .fill(theme.selection.swiftUI)
                    .matchedGeometryEffect(id: "selection", in: selectionNS)
            }
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
            Button("Duplicate") { withAnimation(.snappy) { library.duplicate(file.url) } }
            Button("Show in Finder") { library.reveal(file.url) }
            Divider()
            Button("Move to Trash…", role: .destructive) { trashing = file }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "plus", color: theme.secondary.swiftUI, zoom: z, help: "New calculation (⌘N)", action: createFile)
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

    private var resizeHandle: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { g in
                        let start = dragStartWidth ?? sidebarWidth
                        if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                        sidebarWidth = min(360, max(150, start + g.translation.width / z))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .offset(x: 4)
    }

    // MARK: Files

    private func createFile() {
        if !showSidebar { withAnimation(Self.sidebarSpring) { showSidebar = true } }
        var url: URL?
        withAnimation(.snappy(duration: 0.28)) { url = library.newFile() }
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
        withAnimation(.snappy) { library.rename(url, to: draft) }
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
                    .transition(.opacity)
            }
            Spacer()
            if let total = library.total {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(total, forType: .string)
                    withAnimation(.snappy(duration: 0.18)) { copiedTotal = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                        withAnimation(.easeOut(duration: 0.25)) { copiedTotal = false }
                    }
                } label: {
                    HStack(spacing: 6 * z) {
                        Text(copiedTotal ? "Copied" : "Total").foregroundStyle(theme.secondary.swiftUI)
                            .contentTransition(.opacity)
                        Text(total).foregroundStyle(theme.result.swiftUI).monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy the total")
            }
        }
        .font(.system(size: 12 * z))
        .animation(.snappy(duration: 0.25), value: library.total)
        .animation(.easeInOut(duration: 0.15), value: library.currentLineError)
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
                    .fill(theme.text.swiftUI.opacity(hover && !selected ? 0.05 : 0))
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
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
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
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
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.titlebarSeparatorStyle = .none
            w.appearance = theme.appearance
            w.backgroundColor = theme.background
            w.level = alwaysOnTop ? .floating : .normal
        }
    }
}

extension Notification.Name {
    static let renameCurrent = Notification.Name("TallyRenameCurrent")
    static let toggleSidebar = Notification.Name("TallyToggleSidebar")
    static let newCalculation = Notification.Name("TallyNewCalculation")
}
