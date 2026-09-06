import Foundation

// ENGINE-OWNED · Edges between tasks and windows.
// Pure functions over a VectorStore so they can be tested headlessly.

struct TaskNode: Codable { var id: String; var title: String; var column: String; var color: Int }
struct WindowNode: Codable {
    var id: String; var app: String; var bundle: String; var title: String; var url: String
    var category: String; var lastSeen: Date; var seenCount: Int
}
struct Edge: Codable {
    var taskId: String; var windowId: String; var score: Float; var weight: Float
    var weak: Bool? = nil          // true = below threshold, shown dashed as "closest so far"
}
struct NowTask: Codable { var taskId: String; var title: String; var score: Float }
struct NowInfo: Codable { var windowId: String; var app: String; var title: String; var tasks: [NowTask] }

struct SpaceGraph: Codable {
    var updatedAt: Date
    var trigger: String
    var tasks: [TaskNode]
    var windows: [WindowNode]
    var edges: [Edge]
    var now: NowInfo?
    var storeLabel: String
    var vectorCount: Int
    var millis: Int
}

enum Link {
    /// 1.0 now, 0.5 after `halfLife` hours, and so on.
    static func recency(hoursAgo: Double, halfLife: Double) -> Float {
        Float(pow(0.5, max(0, hoursAgo) / max(0.1, halfLife)))
    }

    static func windowNode(from p: Point) -> WindowNode {
        let f = ISO8601DateFormatter()
        return WindowNode(id: p.id, app: p.payload["app"] ?? "?", bundle: p.payload["bundle"] ?? "", title: p.payload["title"] ?? "",
                          url: p.payload["url"] ?? "", category: p.payload["category"] ?? "unknown",
                          lastSeen: f.date(from: p.payload["lastSeen"] ?? "") ?? .distantPast,
                          seenCount: Int(p.payload["seenCount"] ?? "1") ?? 1)
    }

    /// Build the whole graph: every open task → its related windows; the current window → its tasks.
    static func build(tasks: [Task], taskVectors: [String: [Float]], store: VectorStore, local: LocalStore,
                      threshold: Float, halfLife: Double, perTask: Int,
                      current: (id: String, vector: [Float])?, trigger: String, now: Date = Date()) throws -> SpaceGraph {
        let t0 = Date()
        let f = ISO8601DateFormatter()
        var edges: [Edge] = []
        var linkedWindowIds = Set<String>()
        for t in tasks {
            guard let v = taskVectors[t.id] else { continue }
            let hits = try store.search("windows", vector: v, limit: perTask, filter: [:])
            var any = false
            for h in hits where h.score >= threshold {
                let last = f.date(from: h.payload["lastSeen"] ?? "") ?? now
                let w = h.score * recency(hoursAgo: now.timeIntervalSince(last) / 3600, halfLife: halfLife)
                edges.append(Edge(taskId: t.id, windowId: h.id, score: h.score, weight: w))
                linkedWindowIds.insert(h.id)
                any = true
            }
            // nothing above the line: still show the closest window, dashed, so the map is never empty
            if !any, let h = hits.first, h.score >= 0.12 {
                edges.append(Edge(taskId: t.id, windowId: h.id, score: h.score, weight: h.score * 0.5, weak: true))
                linkedWindowIds.insert(h.id)
            }
        }
        var nowInfo: NowInfo? = nil
        if let c = current, let p = local.get("windows", c.id) {
            let hits = try store.search("tasks", vector: c.vector, limit: 3, filter: [:])
            nowInfo = NowInfo(windowId: c.id, app: p.payload["app"] ?? "", title: p.payload["title"] ?? "",
                              tasks: hits.filter { $0.score >= threshold * 0.8 }.map { NowTask(taskId: $0.id, title: $0.payload["title"] ?? "", score: $0.score) })
        }
        // windows shown: everything linked + the 60 most recent, capped
        var nodes = local.all("windows").map(windowNode(from:))
        nodes.sort { $0.lastSeen > $1.lastSeen }
        let recent = Set(nodes.prefix(60).map { $0.id })
        nodes = nodes.filter { linkedWindowIds.contains($0.id) || recent.contains($0.id) }
        return SpaceGraph(updatedAt: now, trigger: trigger,
                          tasks: tasks.map { TaskNode(id: $0.id, title: $0.title, column: $0.column, color: $0.color) },
                          windows: nodes, edges: edges, now: nowInfo, storeLabel: store.label,
                          vectorCount: (try? store.count("windows")) ?? 0,
                          millis: Int(Date().timeIntervalSince(t0) * 1000))
    }
}
