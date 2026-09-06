import Foundation

// ENGINE-OWNED · Tasks board model.
// A task is a sticky note. Persisted as JSON at
//   ~/Library/Application Support/PixelPet/tasks.json
// Every change posts `.tasksChanged`; the Mind re-embeds tasks on that.

struct Task: Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var text: String = ""
    var column: String = "Today"
    var color: Int = 0                 // index into TaskStore.colors
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var doneAt: Date? = nil
    var mapX: Double? = nil            // where the note sits on the State Space map (0…1 of width)
    var mapY: Double? = nil            // (0…1 of height); nil = default ring layout

    /// What gets embedded.
    var embedText: String { text.isEmpty ? title : title + "\n" + text }
    var isDone: Bool { column == TaskStore.doneColumn }
}

extension Notification.Name {
    static let tasksChanged = Notification.Name("PixelPet.tasksChanged")
    static let spaceRefreshed = Notification.Name("PixelPet.spaceRefreshed")
}

final class TaskStore {
    static let shared = TaskStore()
    static let dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PixelPet")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static let doneColumn = "Done"
    static let colors: [(name: String, hex: String)] = [
        ("yellow", "#FFF2A8"), ("pink", "#FFD6E0"), ("green", "#D5F0D1"), ("blue", "#D2E7FF"), ("orange", "#FFE0B8"),
    ]
    let url = TaskStore.dir.appendingPathComponent("tasks.json")
    let archiveURL = TaskStore.dir.appendingPathComponent("tasks-archive.jsonl")
    var columns = ["Today", "Doing", "Done"]
    private(set) var tasks: [Task] = []

    private let enc: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
    private let dec: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    init() { load() }

    func load() {
        if let d = try? Data(contentsOf: url), let t = try? dec.decode([Task].self, from: d) { tasks = t }
        archiveOld()
    }

    private func save(_ why: String) {
        if let d = try? enc.encode(tasks) { try? d.write(to: url, options: .atomic) }
        Log.w("tasks", "\(why) · \(tasks.count) tasks (\(open.count) open)")
        NotificationCenter.default.post(name: .tasksChanged, object: nil)
    }

    var open: [Task] { tasks.filter { !$0.isDone } }
    func tasks(in column: String) -> [Task] { tasks.filter { $0.column == column }.sorted { $0.createdAt < $1.createdAt } }
    func task(_ id: String) -> Task? { tasks.first { $0.id == id } }

    @discardableResult
    func add(title: String, column: String = "Today", color: Int = 0, at pos: (x: Double, y: Double)? = nil) -> Task {
        var t = Task(title: title, column: column)
        t.color = color
        t.mapX = pos?.x; t.mapY = pos?.y
        tasks.append(t)
        save("added “\(title)”" + (pos != nil ? " on the map" : ""))
        return t
    }

    /// Position-only change: saved quietly (no re-embed needed, but the map re-renders).
    func place(_ id: String, x: Double, y: Double) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].mapX = x; tasks[i].mapY = y
        if let d = try? enc.encode(tasks) { try? d.write(to: url, options: .atomic) }
        Log.w("tasks", "placed “\(tasks[i].title)” at (\(String(format: "%.2f", x)), \(String(format: "%.2f", y)))")
        NotificationCenter.default.post(name: .tasksChanged, object: nil, userInfo: ["placementOnly": true])
    }

    func update(_ t: Task) {
        guard let i = tasks.firstIndex(where: { $0.id == t.id }) else { return }
        var u = t; u.updatedAt = Date()
        if tasks[i] == u { return }
        tasks[i] = u
        save("edited “\(u.title)”")
    }

    func move(_ id: String, to column: String) {
        guard let i = tasks.firstIndex(where: { $0.id == id }), columns.contains(column) else { return }
        tasks[i].column = column
        tasks[i].updatedAt = Date()
        tasks[i].doneAt = column == TaskStore.doneColumn ? Date() : nil
        save("moved “\(tasks[i].title)” → \(column)")
    }

    func delete(_ id: String) {
        guard let t = task(id) else { return }
        tasks.removeAll { $0.id == id }
        save("deleted “\(t.title)”")
    }

    /// Done tasks older than 30 days leave the board (and the vector space) for the archive file.
    func archiveOld(days: Int = 30) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        let old = tasks.filter { $0.isDone && ($0.doneAt ?? $0.updatedAt) < cutoff }
        guard !old.isEmpty else { return }
        if let h = FileHandle(forWritingAtPath: archiveURL.path) ?? { FileManager.default.createFile(atPath: archiveURL.path, contents: nil); return FileHandle(forWritingAtPath: archiveURL.path) }() {
            h.seekToEndOfFile()
            let line = JSONEncoder(); line.dateEncodingStrategy = .iso8601
            for t in old { if let d = try? line.encode(t) { h.write(d); h.write("\n".data(using: .utf8)!) } }
        }
        tasks.removeAll { t in old.contains { $0.id == t.id } }
        save("archived \(old.count) done task(s) older than \(days) days")
    }
}
