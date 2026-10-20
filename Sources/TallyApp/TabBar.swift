import SwiftUI
import UniformTypeIdentifiers

/// Sublime/Chrome-style tab strip that sits in the title bar row, beside the traffic lights.
/// All tabs share one editor, so switching is just swapping the document text.
struct TabBar: View {
    let library: Library
    let theme: Theme
    @Binding var editing: URL?
    @Binding var draft: String
    var renameFocused: FocusState<Bool>.Binding
    let onNew: () -> Void
    let onRename: (URL) -> Void
    let onCommitRename: () -> Void
    let onTrash: (CalcFile) -> Void

    static let height: CGFloat = 38
    @State private var dragging: URL?

    var body: some View {
        HStack(spacing: 0) {
            // Room for the traffic lights; still drags the window.
            TitlebarDragArea(onDoubleClick: onNew).frame(width: 78)
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(library.openTabs, id: \.self) { url in
                                tab(url).id(url)
                            }
                            TitlebarDragArea(onDoubleClick: onNew).frame(minWidth: 40)
                        }
                        .frame(minWidth: geo.size.width, alignment: .leading)
                        .frame(height: Self.height)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: library.selection) { _, sel in
                        if let sel { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(sel) } }
                    }
                }
            }
            controls
        }
        .frame(height: Self.height)
        .background(theme.sidebar.swiftUI)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.text.swiftUI.opacity(0.07)).frame(height: 1) }
    }

    private func name(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    @ViewBuilder
    private func tab(_ url: URL) -> some View {
        let selected = url == library.selection
        TabItem(
            name: name(url), selected: selected, theme: theme,
            isEditing: editing == url, draft: $draft, renameFocused: renameFocused,
            onCommitRename: onCommitRename,
            onCancelRename: { editing = nil },
            onClose: { library.closeTab(url) }
        )
        .onTapGesture(count: 2) { onRename(url) }
        .onTapGesture { if editing != url { library.select(url) } }
        .onDrag {
            dragging = url
            return NSItemProvider(object: url.path as NSString)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(target: url, library: library, dragging: $dragging))
        .contextMenu {
            Button("Rename") { onRename(url) }
            Button("Duplicate") { library.duplicate(url) }
            Button("Show in Finder") { library.reveal(url) }
            Divider()
            Button("Close Tab") { library.closeTab(url) }
            Button("Close Other Tabs") { library.closeOtherTabs(url) }
            Divider()
            Button("Move to Trash…", role: .destructive) {
                if let f = library.files.first(where: { $0.url == url }) { onTrash(f) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "plus", color: theme.secondary.swiftUI, help: "New calculation (⌘T)", action: onNew)
            Menu {
                Section("Calculations") {
                    ForEach(library.files) { file in
                        Button {
                            library.select(file.url)
                        } label: {
                            if library.openTabs.contains(file.url) {
                                Label(file.name, systemImage: "checkmark")
                            } else {
                                Text(file.name)
                            }
                        }
                    }
                }
                Divider()
                Button("Show Tally Folder in Finder") { library.reveal(nil) }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondary.swiftUI)
                    .frame(width: 26, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("All calculations")
        }
        .padding(.horizontal, 6)
    }
}

private struct TabItem: View {
    let name: String
    let selected: Bool
    let theme: Theme
    let isEditing: Bool
    @Binding var draft: String
    var renameFocused: FocusState<Bool>.Binding
    let onCommitRename: () -> Void
    let onCancelRename: () -> Void
    let onClose: () -> Void
    @State private var hover = false
    @State private var hoverClose = false

    var body: some View {
        HStack(spacing: 4) {
            if isEditing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .focused(renameFocused)
                    .onSubmit(onCommitRename)
                    .onChange(of: renameFocused.wrappedValue) { _, f in if !f { onCommitRename() } }
                    .onExitCommand(perform: onCancelRename)
            } else {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(selected ? theme.text.swiftUI : theme.text.swiftUI.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(theme.secondary.swiftUI)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(theme.text.swiftUI.opacity(hoverClose ? 0.12 : 0)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoverClose = $0 }
            .opacity(selected || hover ? 1 : 0)
            .help("Close tab (⌘W)")
        }
        .font(.system(size: 12, weight: selected ? .medium : .regular))
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minWidth: 110, maxWidth: 200, maxHeight: .infinity)
        .background {
            if selected {
                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                    .fill(theme.background.swiftUI)
                    .padding(.top, 6)
            } else if hover {
                UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                    .fill(theme.text.swiftUI.opacity(0.05))
                    .padding(.top, 6)
            }
        }
        .overlay(alignment: .trailing) {
            if !selected { Rectangle().fill(theme.text.swiftUI.opacity(0.08)).frame(width: 1).padding(.vertical, 8) }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct TabDropDelegate: DropDelegate {
    let target: URL
    let library: Library
    @Binding var dragging: URL?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        withAnimation(.snappy(duration: 0.15)) { library.moveTab(d, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Empty title-bar space: drags the window; double-click makes a new tab (as in Sublime and Chrome).
struct TitlebarDragArea: NSViewRepresentable {
    var onDoubleClick: () -> Void

    final class DragView: NSView {
        var onDoubleClick: () -> Void = {}
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { onDoubleClick() } else { window?.performDrag(with: event) }
        }
    }

    func makeNSView(context: Context) -> DragView {
        let v = DragView()
        v.onDoubleClick = onDoubleClick
        return v
    }

    func updateNSView(_ v: DragView, context: Context) { v.onDoubleClick = onDoubleClick }
}
