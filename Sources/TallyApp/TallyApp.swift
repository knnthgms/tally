import SwiftUI
import TallyEngine

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let library = Library.shared

    var body: some Scene {
        Window("Tally", id: "main") {
            ContentView(library: library)
                .frame(minWidth: 560, minHeight: 340)
        }
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 860, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Calculation") { NotificationCenter.default.post(name: .newCalculation, object: nil) }
                    .keyboardShortcut("n")
                Button("Rename…") { NotificationCenter.default.post(name: .renameCurrent, object: nil) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(library.selection == nil)
                Button("Duplicate") { if let s = library.selection { library.duplicate(s) } }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(library.selection == nil)
                Divider()
                Button("Show Tally Folder in Finder") { library.reveal(nil) }
                Button("Change Tally Folder…") { library.chooseFolder() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { library.saveNow() }.keyboardShortcut("s")
                Button("Export with Results…") { library.export() }.keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { library.printDocument() }.keyboardShortcut("p")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Copy All with Results") { library.copyAllWithResults() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Remove Copied Results") { library.removeCopiedResults() }
            }
            SidebarCommands()
            CommandGroup(after: .sidebar) {
                Divider()
                Button("Zoom In") { Zoom.step(1) }.keyboardShortcut("+")
                Button("Zoom Out") { Zoom.step(-1) }.keyboardShortcut("-")
                Button("Actual Size") { Zoom.reset() }.keyboardShortcut("0")
                Divider()
                Button("Previous Calculation") { library.selectAdjacent(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                Button("Next Calculation") { library.selectAdjacent(1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
            }
            CommandMenu("Rates") {
                Button("Refresh Exchange Rates") { library.refreshRates(force: true) }
            }
        }

        Settings {
            SettingsView(library: library)
        }
        .windowResizability(.contentSize)
    }
}

/// Interface zoom (⌘+ / ⌘- / ⌘0), applied on top of the editor font size.
enum Zoom {
    static let levels: [Double] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 2.0]

    static var current: Double { UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1 }

    static func step(_ direction: Int) {
        let i = levels.enumerated().min { abs($0.element - current) < abs($1.element - current) }?.offset ?? 2
        let next = levels[max(0, min(levels.count - 1, i + direction))]
        withAnimation(.snappy(duration: 0.22)) { UserDefaults.standard.set(next, forKey: "zoom") }
    }

    static func reset() {
        withAnimation(.snappy(duration: 0.22)) { UserDefaults.standard.set(1.0, forKey: "zoom") }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ratesTimer: Timer?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-checks periodically; refreshRates skips the fetch unless the configured interval has passed.
        ratesTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            MainActor.assumeIsolated { Library.shared.refreshRates(force: false) }
        }
        // ⌘= zooms in too, like browsers and most apps (the menu item shows ⌘+).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "=" {
                Zoom.step(1)
                return nil
            }
            return event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Library.shared.saveNow() }
    }

    func applicationWillResignActive(_ notification: Notification) {
        MainActor.assumeIsolated { Library.shared.saveNow() }
    }
}
