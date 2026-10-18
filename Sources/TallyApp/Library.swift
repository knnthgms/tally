import AppKit
import Observation
import TallyEngine

struct CalcFile: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// The folder of calculation files, the open document and its results.
@Observable @MainActor
final class Library {
    static let shared = Library()

    private(set) var folder: URL
    private(set) var files: [CalcFile] = []
    private(set) var selection: URL?
    private(set) var text = ""
    private(set) var results: [LineResult] = []
    private(set) var total: String?
    private(set) var ratesUpdated: Date?
    var cursorLine = 0
    /// Bumped when the document is replaced from outside the editor (file switch, external edit).
    private(set) var loadGeneration = 0

    let engine = Engine()
    @ObservationIgnored weak var textView: NSTextView?
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var lastSaved = ""
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?

    static let fileExtension = "txt"

    private init() {
        let d = UserDefaults.standard
        if let path = d.string(forKey: "folder") {
            folder = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Tally", isDirectory: true)
        }
        applySettings()
        if let cached = RatesService.cached() { useRates(cached) }
        openFolder()
        refreshRates(force: false)
    }

    // MARK: Settings

    func applySettings() {
        let d = UserDefaults.standard
        var s = FormatSettings()
        s.decimals = d.object(forKey: "decimals") as? Int ?? 2
        s.grouping = d.object(forKey: "grouping") as? Bool ?? true
        s.use24Hour = d.object(forKey: "use24Hour") as? Bool ?? false
        engine.formatter.settings = s
        engine.anglesInDegrees = d.bool(forKey: "anglesInDegrees")
        evaluate()
        reloadList()
    }

    // MARK: Rates

    private func useRates(_ r: CurrencyRates) {
        var merged = CurrencyRates.fallback.rates
        merged.merge(r.rates) { _, new in new }
        engine.rates = CurrencyRates(rates: merged, updated: r.updated)
        ratesUpdated = r.updated
    }

    func refreshRates(force: Bool) {
        let hours = UserDefaults.standard.object(forKey: "rateHours") as? Double ?? 6
        if !force, let u = ratesUpdated, hours <= 0 || Date().timeIntervalSince(u) < hours * 3600 { return }
        Task {
            if let r = try? await RatesService.fetch() {
                useRates(r)
                evaluate()
            }
        }
    }

    // MARK: Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        saveNow()
        folder = url
        UserDefaults.standard.set(url.path, forKey: "folder")
        selection = nil
        openFolder()
    }

    private func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        reloadList()
        if files.isEmpty {
            let url = folder.appendingPathComponent("Welcome.\(Self.fileExtension)")
            try? Self.welcome.write(to: url, atomically: true, encoding: .utf8)
            reloadList()
        }
        let last = UserDefaults.standard.string(forKey: "lastFile").map { URL(fileURLWithPath: $0) }
        select(files.first { $0.url == last }?.url ?? files.first?.url)
        watch()
    }

    func reloadList() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles])) ?? []
        files = urls.filter { $0.pathExtension.lowercased() == Self.fileExtension }
            .map { CalcFile(url: $0.standardizedFileURL) }
            .sorted(by: Self.sortOrder)
        if let s = selection, !files.contains(where: { $0.url == s }) {
            selection = nil
            select(files.first?.url)
        }
    }

    private static func sortOrder(_ a: CalcFile, _ b: CalcFile) -> Bool {
        if UserDefaults.standard.string(forKey: "sortMode") == "modified" {
            let da = (try? a.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if da != db { return da > db }
        }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// What a click on a result copies, per the "copy" setting.
    func copyText(line: Int) -> String? {
        guard line < results.count, let v = results[line].value else { return nil }
        return UserDefaults.standard.string(forKey: "copyMode") == "number"
            ? engine.formatter.numberOnly(v) : engine.formatter.format(v)
    }

    private func watch() {
        watcher?.cancel()
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete],
                                                            queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadList()
                self?.reloadIfChangedOnDisk()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    /// Picks up edits made in another editor, as long as there are no unsaved local changes.
    func reloadIfChangedOnDisk() {
        guard let url = selection, saveWork == nil,
              let disk = try? String(contentsOf: url, encoding: .utf8), disk != lastSaved else { return }
        lastSaved = disk
        text = disk
        loadGeneration += 1
        evaluate()
    }

    // MARK: Documents

    func select(_ url: URL?) {
        guard url != selection || url == nil else { return }
        saveNow()
        selection = url
        let content = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        text = content
        lastSaved = content
        loadGeneration += 1
        if let url { UserDefaults.standard.set(url.path, forKey: "lastFile") }
        evaluate()
    }

    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        evaluate()
        scheduleSave()
    }

    func evaluate() {
        results = engine.evaluate(text)
        total = engine.total(results).map { engine.formatter.format($0) }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard let url = selection, text != lastSaved else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            lastSaved = text
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func uniqueURL(_ base: String) -> URL {
        var n = 1
        while true {
            let name = n == 1 ? base : "\(base) \(n)"
            let url = folder.appendingPathComponent("\(name).\(Self.fileExtension)").standardizedFileURL
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    @discardableResult
    func newFile(named base: String = "Untitled", content: String = "") -> URL {
        let url = uniqueURL(base)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        reloadList()
        select(url)
        return url
    }

    func duplicate(_ url: URL) {
        saveNow()
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        newFile(named: url.deletingPathExtension().lastPathComponent + " copy", content: content)
    }

    func rename(_ url: URL, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty else { return }
        saveNow()
        let dest = folder.appendingPathComponent("\(clean).\(Self.fileExtension)").standardizedFileURL
        guard dest != url else { return }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            let wasSelected = selection == url
            if wasSelected { selection = dest; UserDefaults.standard.set(dest.path, forKey: "lastFile") }
            reloadList()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Moves the file to the Trash (recoverable from Finder).
    func trash(_ url: URL) {
        if selection == url { saveNow() }
        NSWorkspace.shared.recycle([url]) { [weak self] _, _ in
            Task { @MainActor in self?.reloadList() }
        }
    }

    func reveal(_ url: URL?) {
        if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { NSWorkspace.shared.open(folder) }
    }

    // MARK: Export

    /// The document with each result appended, columns aligned.
    func textWithResults() -> String {
        let lines = text.components(separatedBy: "\n")
        let width = min(60, lines.map(\.count).max() ?? 0)
        return zip(lines, results).map { line, r in
            guard let d = r.display else { return line }
            return line.padding(toLength: max(width, line.count), withPad: " ", startingAt: 0) + "  = " + d
        }.joined(separator: "\n")
    }

    func export() {
        saveNow()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (selection?.deletingPathExtension().lastPathComponent ?? "Calculation") + " (results).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? textWithResults().write(to: url, atomically: true, encoding: .utf8)
    }

    func copyAllWithResults() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textWithResults(), forType: .string)
    }

    func printDocument() {
        guard let tv = textView else { return }
        let op = NSPrintOperation(view: tv)
        op.printInfo.isVerticallyCentered = false
        op.printInfo.horizontalPagination = .fit
        op.run()
    }

    var currentLineError: String? {
        guard cursorLine < results.count, results[cursorLine].kind == .error else { return nil }
        return results[cursorLine].error
    }

    static let welcome = """
    # Welcome to Tally
    // Each file in your Tally folder is plain text — edit it here or anywhere else.

    Price: $6 times 5
    Fee: 8 CHF in Euro
    sum in USD - 9%

    # Units & conversions
    5 feet 3 inches in cm
    20 ml in tea spoons
    60 km/h in mph
    1 GiB in MB
    100 °C in F

    # Percentages
    20% of 150
    $80 + 15%
    50 as a % of 200
    20% of what is 30 cm

    # Variables, dates & time
    rent = $1,450
    rent * 12
    next friday + 2 weeks
    time in Tokyo
    2:30 pm HKT in Berlin

    # Maths
    sqrt(16) + 2^10
    255 in hex
    """
}
