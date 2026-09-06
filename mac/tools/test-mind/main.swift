import Foundation

// Headless test of the Mind core: embed → store → link. No AppKit UI, no app state.
//   tools/test-mind.sh
var failures = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ✓ " : "  ✗ ") + name + (detail.isEmpty ? "" : "  (\(detail))"))
    if !ok { failures += 1 }
}

let embedder = Embed.makeDefault()
print("embedder: \(embedder.name) \(embedder.dim)-d")

let texts: [(String, String)] = [
    ("code-vscode",  "Code · Behavior.swift — Pet-adhd · Swift pixel pet macOS AppKit window ledges physics"),
    ("code-github",  "Google Chrome · ActianCorp/Vector-Docker: Docker build file · github.com"),
    ("music",        "Spotify · Lo-fi beats to relax and study to"),
    ("mail",         "Mail · Re: invoice for September · accounting"),
    ("docs-actian",  "Google Chrome · VectorAI DB REST API — create collection, upsert points, search · docs.vectoraidb.actian.com"),
    ("youtube",      "Google Chrome · Funny cat compilation 2026 · youtube.com"),
]
var vectors: [String: [Float]] = [:]
for (id, t) in texts { vectors[id] = embedder.embed(t) }
check("every text embeds", vectors.values.allSatisfy { $0.count == embedder.dim })
check("vectors are unit length", vectors.values.allSatisfy { abs(sqrt($0.reduce(0) { $0 + $1 * $1 }) - 1) < 0.01 })

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pixelpet-test-\(UUID().uuidString).json")
let store = LocalStore(url: tmp)
try store.ensureCollection("windows", dim: embedder.dim)
try store.ensureCollection("tasks", dim: embedder.dim)
let iso = ISO8601DateFormatter()
let now = Date()
var pts: [Point] = []
for (id, t) in texts {
    let age: Double = id == "youtube" ? 30 : 0.2   // youtube seen 30 h ago
    pts.append(Point(id: id, vector: vectors[id]!, payload: ["app": String(t.split(separator: "·")[0]).trimmingCharacters(in: .whitespaces),
                                                              "title": t, "category": "x", "lastSeen": iso.string(from: now.addingTimeInterval(-age * 3600)), "seenCount": "1"]))
}
try store.upsert("windows", pts)
check("store holds 6 windows", (try store.count("windows")) == 6)

let taskA = Task(id: "task-actian", title: "Wire Actian VectorAI DB into PixelPet", text: "REST client, create collections, upsert, search", column: "Today")
let taskB = Task(id: "task-invoice", title: "Send September invoice", text: "accounting, email the PDF", column: "Today")
let tv: [String: [Float]] = ["task-actian": embedder.embed(taskA.embedText)!, "task-invoice": embedder.embed(taskB.embedText)!]
try store.upsert("tasks", [Point(id: taskA.id, vector: tv[taskA.id]!, payload: ["title": taskA.title]), Point(id: taskB.id, vector: tv[taskB.id]!, payload: ["title": taskB.title])])

let hitsA = try store.search("windows", vector: tv["task-actian"]!, limit: 6, filter: [:])
print("  nearest to “\(taskA.title)”: " + hitsA.prefix(3).map { "\($0.id) \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))
check("actian docs rank above music for the Actian task", (hitsA.firstIndex { $0.id == "docs-actian" } ?? 9) < (hitsA.firstIndex { $0.id == "music" } ?? 9))
check("github/docker ranks above youtube for the Actian task", (hitsA.firstIndex { $0.id == "code-github" } ?? 9) < (hitsA.firstIndex { $0.id == "youtube" } ?? 9))
let hitsB = try store.search("windows", vector: tv["task-invoice"]!, limit: 6, filter: [:])
print("  nearest to “\(taskB.title)”: " + hitsB.prefix(3).map { "\($0.id) \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))
check("mail is the top hit for the invoice task", hitsB.first?.id == "mail")

check("recency: now = 1.0", abs(Link.recency(hoursAgo: 0, halfLife: 6) - 1) < 0.001)
check("recency: one half-life = 0.5", abs(Link.recency(hoursAgo: 6, halfLife: 6) - 0.5) < 0.001)

let g = try Link.build(tasks: [taskA, taskB], taskVectors: tv, store: store, local: store, threshold: 0.25, halfLife: 6, perTask: 10,
                       current: ("docs-actian", vectors["docs-actian"]!), trigger: "test", now: now)
check("graph has both tasks", g.tasks.count == 2)
check("graph has edges", !g.edges.isEmpty, "\(g.edges.count)")
check("every edge is above threshold (or a weak hint)", g.edges.allSatisfy { $0.score >= 0.25 || $0.weak == true })
check("weights never exceed scores (recency ≤ 1)", g.edges.allSatisfy { $0.weight <= $0.score + 0.0001 })
if let yt = g.edges.first(where: { $0.windowId == "youtube" }) { check("30-hour-old window is discounted", yt.weight < yt.score * 0.1) }
check("now → Actian task first", g.now?.tasks.first?.taskId == "task-actian", g.now?.tasks.map { "\($0.taskId) \(String(format: "%.2f", $0.score))" }.joined(separator: ", ") ?? "none")

let filtered = try store.search("windows", vector: tv["task-actian"]!, limit: 6, filter: ["app": "Spotify"])
check("payload filter works", filtered.count == 1 && filtered.first?.id == "music")
try store.delete("windows", ids: ["music"])
check("delete works", (try store.count("windows")) == 5)
store.saveNow()
let reloaded = LocalStore(url: tmp)
check("store round-trips through disk", (try reloaded.count("windows")) == 5)
try? FileManager.default.removeItem(at: tmp)

print(failures == 0 ? "\nmind core: all good" : "\nmind core: \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
