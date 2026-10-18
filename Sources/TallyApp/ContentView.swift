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

    @State private var renaming: CalcFile?
    @State private var newName = ""
    @State private var trashing: CalcFile?
    @State private var toast: String?

    private var theme: Theme { Theme.named(themeID) }
    private let barHeight: CGFloat = 38

    private var style: EditorStyle {
        EditorStyle(theme: theme, fontID: fontID, fontSize: fontSize, lineSpacing: lineSpacing,
                    resultFraction: resultFraction, highlightLine: highlightLine)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sidebar
                    .frame(width: 200)
                    .transition(.move(edge: .leading))
                Rectangle().fill(theme.text.swiftUI.opacity(0.07)).frame(width: 1)
            }
            VStack(spacing: 0) {
                topBar
                if library.selection != nil {
                    EditorView(library: library, style: style)
                } else {
                    VStack(spacing: 8) {
                        Text("No calculation").font(.title3)
                        Text("Press ⌘N to start one.").foregroundStyle(theme.secondary.swiftUI)
                    }
                    .foregroundStyle(theme.text.swiftUI)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showTotal { footer }
            }
            .background(theme.background.swiftUI)
        }
        .overlay(alignment: .topLeading) {
            // Sits just right of the traffic lights in both layouts.
            IconButton(symbol: "sidebar.left", color: theme.secondary.swiftUI, help: "Toggle sidebar (⌘\\)") {
                withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
            }
            .padding(.leading, 78)
            .frame(height: barHeight)
        }
        .background(theme.background.swiftUI)
        .ignoresSafeArea()
        .background(WindowConfigurator(theme: theme, alwaysOnTop: alwaysOnTop))
        .preferredColorScheme(theme.isDark.map { $0 ? .dark : .light })
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let f = renaming { library.rename(f.url, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Move “\(trashing?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } })) {
            Button("Move to Trash", role: .destructive) { if let f = trashing { library.trash(f.url) }; trashing = nil }
        } message: {
            Text("You can restore it from the Trash in Finder.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .renameCurrent)) { _ in
            if let f = library.files.first(where: { $0.url == library.selection }) { startRename(f) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) { showSidebar.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.reloadList()
            library.reloadIfChangedOnDisk()
        }
    }

    // MARK: Pieces

    private var currentName: String {
        library.files.first { $0.url == library.selection }?.name ?? "Tally"
    }

    private var topBar: some View {
        ZStack {
            WindowDragArea()
            if showTitle {
                Text(currentName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondary.swiftUI)
                    .lineLimit(1)
                    .allowsHitTesting(false)
                    .padding(.horizontal, 120)
            }
            HStack {
                Spacer()
                IconButton(symbol: "plus", color: theme.secondary.swiftUI, help: "New calculation (⌘N)") { library.newFile() }
                    .padding(.trailing, 12)
            }
        }
        .frame(height: barHeight)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            WindowDragArea().frame(height: barHeight)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(library.files) { file in
                        FileRow(name: file.name, selected: file.url == library.selection, theme: theme)
                            .onTapGesture { library.select(file.url) }
                            .contextMenu {
                                Button("Rename…") { startRename(file) }
                                Button("Duplicate") { library.duplicate(file.url) }
                                Button("Show in Finder") { library.reveal(file.url) }
                                Divider()
                                Button("Move to Trash…", role: .destructive) { trashing = file }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            HStack {
                IconButton(symbol: "folder", color: theme.secondary.swiftUI, help: "Open the Tally folder in Finder") {
                    library.reveal(nil)
                }
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(theme.secondary.swiftUI)
                        .frame(width: 26, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(theme.sidebar.swiftUI)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let err = library.currentLineError {
                Image(systemName: "exclamationmark.circle").foregroundStyle(theme.variable.swiftUI)
                Text(err).foregroundStyle(theme.secondary.swiftUI).lineLimit(1).truncationMode(.tail)
            }
            Spacer()
            if let total = library.total {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(total, forType: .string)
                    toast = "Copied"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { toast = nil }
                } label: {
                    HStack(spacing: 6) {
                        Text("Total").foregroundStyle(theme.secondary.swiftUI)
                        Text(toast ?? total).foregroundStyle(theme.result.swiftUI).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
                .help("Click to copy")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 22)
        .frame(height: 30)
        .background(theme.text.swiftUI.opacity(0.03))
    }

    private func startRename(_ f: CalcFile) {
        newName = f.name
        renaming = f
    }
}

struct FileRow: View {
    let name: String
    let selected: Bool
    let theme: Theme
    @State private var hover = false

    var body: some View {
        Text(name)
            .font(.system(size: 13, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? theme.text.swiftUI : theme.text.swiftUI.opacity(0.75))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? theme.selection.swiftUI : theme.text.swiftUI.opacity(hover ? 0.05 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

struct IconButton: View {
    let symbol: String
    let color: Color
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(color.opacity(hover ? 1 : 0.8))
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(hover ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// Lets the borderless title area move the window, and double-click zoom like a real title bar.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Applies window chrome settings SwiftUI doesn't expose: transparent title bar, theme appearance, float on top.
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
            w.isMovableByWindowBackground = false
            w.appearance = theme.appearance
            w.backgroundColor = theme.background
            w.level = alwaysOnTop ? .floating : .normal
            w.collectionBehavior.insert(.fullScreenPrimary)
        }
    }
}

extension Notification.Name {
    static let renameCurrent = Notification.Name("TallyRenameCurrent")
    static let toggleSidebar = Notification.Name("TallyToggleSidebar")
}
