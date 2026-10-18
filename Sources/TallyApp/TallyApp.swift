import SwiftUI
import TallyEngine

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private let library = Library.shared

    var body: some Scene {
        Window("Tally", id: "main") {
            ContentView(library: library)
                .frame(minWidth: 620, minHeight: 360)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 860, height: 580)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Calculation") { library.newFile() }.keyboardShortcut("n")
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
            }
            CommandMenu("Rates") {
                Button("Refresh Exchange Rates") { library.refreshRates(force: true) }
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { NotificationCenter.default.post(name: .toggleSidebar, object: nil) }
                    .keyboardShortcut("\\", modifiers: .command)
            }
            CommandGroup(after: .textFormatting) {
                Button("Bigger") { adjustFont(1) }.keyboardShortcut("+")
                Button("Smaller") { adjustFont(-1) }.keyboardShortcut("-")
                Button("Actual Size") { UserDefaults.standard.set(15.0, forKey: "fontSize") }.keyboardShortcut("0")
            }
        }

        Settings {
            SettingsView(library: library)
        }
    }

    private func adjustFont(_ delta: Double) {
        let d = UserDefaults.standard
        let size = (d.object(forKey: "fontSize") as? Double ?? 15) + delta
        d.set(min(32, max(10, size)), forKey: "fontSize")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var ratesTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-checks periodically; refreshRates skips the fetch unless the configured interval has passed.
        ratesTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { _ in
            MainActor.assumeIsolated { Library.shared.refreshRates(force: false) }
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
