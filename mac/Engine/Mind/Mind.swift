import AppKit

// ENGINE-OWNED · The coordinator for the State Space.
//   capture → embed → store → link → notify, on its own serial queue.
// Triggers: focus / new window (debounced 2 s), a full sweep every N minutes, manual.
// The pet loop never waits on this.

struct MindSettings {
    private static let d = UserDefaults.standard
    static var enabled: Bool { get { d.object(forKey: "mind.enabled") as? Bool ?? true } set { d.set(newValue, forKey: "mind.enabled") } }
    static var titlesOnly: Bool { get { d.bool(forKey: "mind.titlesOnly") } set { d.set(newValue, forKey: "mind.titlesOnly") } }
    static var exclusions: [String] {
        get { d.stringArray(forKey: "mind.exclusions") ?? ["com.1password", "com.agilebits", "com.apple.keychainaccess", "com.apple.Passwords", "Private Browsing", "Incognito"] }
        set { d.set(newValue, forKey: "mind.exclusions") }
    }
    static var threshold: Double { get { d.object(forKey: "mind.threshold") as? Double ?? 0.37 } set { d.set(newValue, forKey: "mind.threshold") } }
    static var halfLifeHours: Double { get { d.object(forKey: "mind.halfLife") as? Double ?? 6 } set { d.set(newValue, forKey: "mind.halfLife") } }
    static var sweepMinutes: Double { get { d.object(forKey: "mind.sweepMinutes") as? Double ?? 5 } set { d.set(newValue, forKey: "mind.sweepMinutes") } }
    static var actianEnabled: Bool { get { d.bool(forKey: "mind.actian.enabled") } set { d.set(newValue, forKey: "mind.actian.enabled") } }
    static var actianEndpoint: String { get { d.string(forKey: "mind.actian.endpoint") ?? "http://localhost:6575" } set { d.set(newValue, forKey: "mind.actian.endpoint") } }
    static var actianToken: String { get { d.string(forKey: "mind.actian.token") ?? "" } set { d.set(newValue, forKey: "mind.actian.token") } }
    static var maxWindows: Int { get { d.object(forKey: "mind.maxWindows") as? Int ?? 3000 } set { d.set(newValue, forKey: "mind.maxWindows") } }
    static var maxPerApp: Int { get { d.object(forKey: "mind.maxPerApp") as? Int ?? 40 } set { d.set(newValue, forKey: "mind.maxPerApp") } }
}

/// What the Mind needs from the live world, read on the main thread.
struct MindWorld {
    var context: ScreenContext
    var frontPID: Int32
    var frontWindowId: Int
    var desktop: UInt64
    var visible: [(pid: Int32, app: String)]
}

final class Mind {
    static let shared = Mind()
    let queue = DispatchQueue(label: "pixelpet.mind", qos: .utility)
    let embedder: Embedder
    let local: LocalStore
    private(set) var remote: ActianStore?
    private(set) var graph: SpaceGraph?           // read on main
    private(set) var lastCapture: Snapshot?
    private(set) var busy = false
    var worldProvider: (() -> MindWorld)?
    private var debounce: DispatchWorkItem?
    private var sweepTimer: Timer?
    private var taskVectors: [String: [Float]] = [:]
    private var currentNode: (id: String, vector: [Float])?
    private let snapshotsURL = TaskStore.dir.appendingPathComponent("snapshots.jsonl")
    private let edgesURL = TaskStore.dir.appendingPathComponent("edges.json")
    private let iso = ISO8601DateFormatter()
    var nextSweep = Date()

    private init() {
        embedder = Embed.makeDefault()
        local = LocalStore(url: TaskStore.dir.appendingPathComponent("vectors.local.json"))
    }

    var store: VectorStore { (remote?.reachable ?? false) ? remote! : local }

    // MARK: lifecycle

    func start() {
        guard MindSettings.enabled else { Log.w("state-space", "disabled in settings"); return }
        Log.w("state-space", "starting · embedder \(embedder.name) \(embedder.dim)-d · local vectors: \((try? local.count("windows")) ?? 0) windows, \((try? local.count("tasks")) ?? 0) tasks")
        // the embedding recipe changed: rebuild every vector and reset the threshold to the new scale
        let recipe = 3
        if UserDefaults.standard.integer(forKey: "mind.recipe") != recipe {
            let w = local.all("windows").map { $0.id }, t = local.all("tasks").map { $0.id }
            if !w.isEmpty { try? local.delete("windows", ids: w) }
            if !t.isEmpty { try? local.delete("tasks", ids: t) }
            UserDefaults.standard.removeObject(forKey: "mind.threshold")
            UserDefaults.standard.set(recipe, forKey: "mind.recipe")
            Log.w("store", "embedding recipe v\(recipe) (\(embedder.name)): cleared \(w.count) window + \(t.count) task vectors; threshold reset to \(MindSettings.threshold)")
        }
        // vectors from a different embedder can't be compared: start over if the dimension changed
        if let any = local.all("windows").first ?? local.all("tasks").first, any.vector.count != embedder.dim {
            Log.w("store", "embedding dimension changed (\(any.vector.count) → \(embedder.dim)); clearing local vectors")
            try? local.delete("windows", ids: local.all("windows").map { $0.id })
            try? local.delete("tasks", ids: local.all("tasks").map { $0.id })
        }
        try? local.ensureCollection("windows", dim: embedder.dim)
        try? local.ensureCollection("tasks", dim: embedder.dim)
        configureRemote()
        NotificationCenter.default.addObserver(forName: .tasksChanged, object: nil, queue: nil) { [weak self] n in
            if (n.userInfo?["placementOnly"] as? Bool) == true { return }
            self?.queue.async { self?.embedTasks(); self?.refresh(trigger: "tasks") }
        }
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in self?.embedTasks(); self?.sweep(trigger: "start") }
        scheduleSweep()
    }

    func configureRemote() {
        queue.async { [self] in
            remote = nil
            guard MindSettings.actianEnabled, let url = URL(string: MindSettings.actianEndpoint) else { return }
            let r = ActianStore(endpoint: url, token: MindSettings.actianToken)
            if r.health() {
                do {
                    try r.ensureCollection("windows", dim: embedder.dim)
                    try r.ensureCollection("tasks", dim: embedder.dim)
                    remote = r
                    Log.w("store", "actian connected at \(url.absoluteString)")
                    // replay everything local into the remote (idempotent upserts)
                    let w = local.all("windows"), t = local.all("tasks")
                    if !w.isEmpty { try r.upsert("windows", w) }
                    if !t.isEmpty { try r.upsert("tasks", t) }
                    Log.w("store", "actian: mirrored \(w.count) windows, \(t.count) tasks")
                } catch { Log.w("store", "actian setup failed: \(error)") }
            } else {
                Log.w("store", "actian unreachable at \(url.absoluteString): \(r.lastError) → using local store")
            }
        }
    }

    /// One-shot connection test for the settings pane (runs on the caller's thread).
    func testActian(endpoint: String, token: String) -> String {
        guard let url = URL(string: endpoint) else { return "Bad URL" }
        let r = ActianStore(endpoint: url, token: token)
        if r.health() {
            let n = (try? r.count("windows")) ?? -1
            return "Connected · windows collection: \(n < 0 ? "not created yet" : "\(n) vectors")"
        }
        return "Not reachable: \(r.lastError)"
    }

    private func scheduleSweep() {
        sweepTimer?.invalidate()
        let every = max(60, MindSettings.sweepMinutes * 60)
        nextSweep = Date().addingTimeInterval(every)
        sweepTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in
            self?.nextSweep = Date().addingTimeInterval(every)
            self?.queue.async { self?.sweep(trigger: "sweep") }
        }
    }

    // MARK: triggers (main thread)

    /// Focus changed or the set of windows changed. Debounced.
    func windowChanged() {
        guard MindSettings.enabled else { return }
        debounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.queue.async { self?.captureFocused(); self?.refresh(trigger: "focus") } }
        debounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: w)
    }

    /// You moved to another desktop: the accessibility API only lists windows on the
    /// desktop you're looking at, so each desktop gets swept when you arrive on it.
    private var desktopDebounce: DispatchWorkItem?
    func desktopChanged() {
        guard MindSettings.enabled else { return }
        desktopDebounce?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.queue.async { self?.sweep(trigger: "desktop") } }
        desktopDebounce = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
    }

    func refreshNow() {
        queue.async { [weak self] in self?.sweep(trigger: "manual") }
    }

    // MARK: pipeline (mind queue)

    private func world() -> MindWorld? {
        guard let p = worldProvider else { return nil }
        if Thread.isMainThread { return p() }
        return DispatchQueue.main.sync { p() }
    }

    /// System pieces that are never meaningful as "windows you work in".
    static let systemBundles = ["com.apple.SecurityAgent", "com.apple.loginwindow", "com.apple.dock", "com.apple.WindowManager",
                                "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight", "com.apple.UserNotificationCenter"]
    private func isSystem(_ s: Snapshot) -> Bool {
        Mind.systemBundles.contains { s.bundle.hasPrefix($0) } || s.app == "SecurityAgent" || s.app == "loginwindow"
    }

    private func excluded(_ s: Snapshot) -> Bool {
        let hay = (s.bundle + " " + s.title).lowercased()
        return MindSettings.exclusions.contains { !$0.isEmpty && hay.contains($0.lowercased()) }
    }

    private var wasAway = false
    private func captureFocused() {
        guard let w = world(), !w.context.app.isEmpty else { return }
        if w.context.category == .away { wasAway = true; return }
        if wasAway {
            wasAway = false
            Log.w("capture", "back from the lock screen → full sweep")
            queue.async { [weak self] in self?.sweep(trigger: "unlock") }
        }
        var s = Capture.focused(w.context, pid: w.frontPID, windowId: w.frontWindowId, desktop: w.desktop, withText: !MindSettings.titlesOnly)
        if isSystem(s) { return }
        if excluded(s) { s.text = ""; s.hash = Capture.sha(s.embedText) }
        ingest(s, source: "focus")
        currentNode = (s.nodeId, taskVectorsCacheWindow[s.nodeId] ?? (local.get("windows", s.nodeId)?.vector ?? []))
        lastCapture = s
    }

    private var taskVectorsCacheWindow: [String: [Float]] = [:]

    private func sweep(trigger: String) {
        guard let w = world() else { return }
        busy = true
        let t0 = Date()
        var n = 0
        // every ordinary app that's running, on any desktop (AX lists their windows regardless of Space)
        let me = ProcessInfo.processInfo.processIdentifier
        var apps: [(pid: Int32, app: String)] = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && !$0.isTerminated }
            .map { ($0.processIdentifier, $0.localizedName ?? "?") }
        for v in w.visible where !apps.contains(where: { $0.pid == v.pid }) { apps.append(v) }
        var seenPids = Set<Int32>()
        var appCount = 0
        var perApp: [String] = []
        for v in apps.prefix(40) where !seenPids.contains(v.pid) {
            seenPids.insert(v.pid)
            appCount += 1
            let bundle = NSRunningApplication(processIdentifier: v.pid)?.bundleIdentifier ?? ""
            if Mind.systemBundles.contains(where: { bundle.hasPrefix($0) }) { continue }
            let cat = Context.classify(bundle: bundle, app: v.app, url: "", title: "").rawValue
            let found = Capture.windows(ofPid: v.pid, app: v.app, bundle: bundle, category: cat, desktop: w.desktop)
            perApp.append("\(v.app):\(found.count)")
            for s in found {
                if isSystem(s) { continue }
                var s2 = s
                if excluded(s2) { s2.text = "" }
                if local.get("windows", s2.nodeId) == nil { ingest(s2, source: "sweep"); n += 1 } else { touch(s2.nodeId) }
            }
        }
        captureFocused()
        Log.w("capture", "sweep windows per app (this desktop only; others are swept when you switch to them): " + perApp.joined(separator: ", "))
        Log.w("capture", "sweep(\(trigger)): \(appCount) apps on all desktops, \(n) new window nodes, \(Int(Date().timeIntervalSince(t0) * 1000)) ms\(Context.accessibilityGranted ? "" : " (no Accessibility: titles unavailable)")")
        refresh(trigger: trigger)
        busy = false
    }

    private func touch(_ id: String) {
        guard var p = local.get("windows", id) else { return }
        p.payload["lastSeen"] = iso.string(from: Date())
        p.payload["seenCount"] = String((Int(p.payload["seenCount"] ?? "1") ?? 1) + 1)
        try? local.upsert("windows", [p])
    }

    /// Store one snapshot as a window node; re-embed only when its content changed.
    private func ingest(_ s: Snapshot, source: String) {
        appendSnapshot(s)
        let existing = local.get("windows", s.nodeId)
        var payload = existing?.payload ?? [:]
        payload["kind"] = "window"; payload["app"] = s.app; payload["bundle"] = s.bundle; payload["title"] = s.title
        payload["url"] = s.url; payload["document"] = s.document; payload["category"] = s.category
        payload["desktop"] = String(s.desktop); payload["lastSeen"] = iso.string(from: s.time)
        payload["seenCount"] = String((Int(payload["seenCount"] ?? "0") ?? 0) + 1)
        if payload["firstSeen"] == nil { payload["firstSeen"] = payload["lastSeen"] }
        if !s.text.isEmpty { payload["textSample"] = String(s.text.prefix(300)) }
        var vector = existing?.vector ?? []
        if existing == nil || payload["hash"] != s.hash || vector.isEmpty {
            let t0 = Date()
            guard let v = embedder.embed(s.embedText) else { Log.w("embed", "no vector for \(s.app) “\(s.title)” (empty text?)"); return }
            vector = v
            payload["hash"] = s.hash
            Log.w("embed", "\(source): \(s.app) “\(s.title.prefix(60))” \(s.text.isEmpty ? "title only" : "\(s.text.count) chars") · \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        }
        let p = Point(id: s.nodeId, vector: vector, payload: payload)
        try? local.upsert("windows", [p])
        if !s.title.isEmpty || !s.url.isEmpty {
            let stale = local.all("windows").filter { $0.id != s.nodeId && $0.payload["bundle"] == s.bundle && ($0.payload["title"] ?? "").isEmpty && ($0.payload["url"] ?? "").isEmpty }.map { $0.id }
            if !stale.isEmpty { try? local.delete("windows", ids: stale); if let r = remote, r.reachable { try? r.delete("windows", ids: stale) } }
        }
        taskVectorsCacheWindow[s.nodeId] = vector
        if let r = remote, r.reachable { do { try r.upsert("windows", [p]) } catch { Log.w("store", "actian upsert failed: \(error) → local only until next sweep") } }
        enforceRetention()
    }

    private func appendSnapshot(_ s: Snapshot) {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let d = try? e.encode(s) else { return }
        if !FileManager.default.fileExists(atPath: snapshotsURL.path) { FileManager.default.createFile(atPath: snapshotsURL.path, contents: nil) }
        if let size = try? FileManager.default.attributesOfItem(atPath: snapshotsURL.path)[.size] as? Int, size > 20_000_000 {
            try? FileManager.default.removeItem(at: snapshotsURL.deletingLastPathComponent().appendingPathComponent("snapshots.1.jsonl"))
            try? FileManager.default.moveItem(at: snapshotsURL, to: snapshotsURL.deletingLastPathComponent().appendingPathComponent("snapshots.1.jsonl"))
            FileManager.default.createFile(atPath: snapshotsURL.path, contents: nil)
        }
        if let h = FileHandle(forWritingAtPath: snapshotsURL.path) { h.seekToEndOfFile(); h.write(d); h.write("\n".data(using: .utf8)!); try? h.close() }
    }

    /// Keep the window collection under the caps (Actian Community: 5,000 vectors).
    private func enforceRetention() {
        let all = local.all("windows")
        guard all.count > MindSettings.maxWindows || all.count % 25 == 0 else { return }
        var victims: [String] = []
        var byApp: [String: [Point]] = [:]
        for p in all { byApp[p.payload["bundle"] ?? "", default: []].append(p) }
        for (_, ps) in byApp where ps.count > MindSettings.maxPerApp {
            let sorted = ps.sorted { ($0.payload["lastSeen"] ?? "") < ($1.payload["lastSeen"] ?? "") }
            victims += sorted.prefix(ps.count - MindSettings.maxPerApp).map { $0.id }
        }
        let remaining = all.count - victims.count
        if remaining > MindSettings.maxWindows {
            let sorted = all.filter { !victims.contains($0.id) }.sorted { ($0.payload["lastSeen"] ?? "") < ($1.payload["lastSeen"] ?? "") }
            victims += sorted.prefix(remaining - MindSettings.maxWindows).map { $0.id }
        }
        guard !victims.isEmpty else { return }
        try? local.delete("windows", ids: victims)
        if let r = remote, r.reachable { try? r.delete("windows", ids: victims) }
        Log.w("store", "retention: evicted \(victims.count) old window nodes")
    }

    private func embedTasks() {
        let ts = TaskStore.shared.tasks
        var points: [Point] = []
        for t in ts {
            let hash = Capture.sha(t.embedText)
            if let p = local.get("tasks", t.id), p.payload["hash"] == hash, !p.vector.isEmpty {
                taskVectors[t.id] = p.vector
                var q = p; q.payload["column"] = t.column; q.payload["title"] = t.title
                points.append(q)
                continue
            }
            guard let v = embedder.embed(t.embedText) else { continue }
            taskVectors[t.id] = v
            points.append(Point(id: t.id, vector: v, payload: ["kind": "task", "title": t.title, "text": String(t.text.prefix(300)), "column": t.column,
                                                              "color": String(t.color), "hash": hash, "createdAt": iso.string(from: t.createdAt)]))
            Log.w("embed", "task “\(t.title)”")
        }
        let gone = Set(local.all("tasks").map { $0.id }).subtracting(ts.map { $0.id })
        if !gone.isEmpty { try? local.delete("tasks", ids: Array(gone)); if let r = remote, r.reachable { try? r.delete("tasks", ids: Array(gone)) } }
        if !points.isEmpty { try? local.upsert("tasks", points); if let r = remote, r.reachable { try? r.upsert("tasks", points) } }
    }

    private func refresh(trigger: String) {
        let tasks = TaskStore.shared.open
        if taskVectors.isEmpty && !tasks.isEmpty { embedTasks() }
        do {
            let g = try Link.build(tasks: tasks, taskVectors: taskVectors, store: store, local: local,
                                   threshold: Float(MindSettings.threshold), halfLife: MindSettings.halfLifeHours, perTask: 15,
                                   current: currentNode, trigger: trigger)
            let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
            if let d = try? e.encode(g) { try? d.write(to: edgesURL, options: .atomic) }
            let nowLine = g.now.map { n in n.tasks.isEmpty ? "now: \(n.app) → no task above threshold" : "now: \(n.app) → \(n.tasks.map { "“\($0.title)” \(String(format: "%.2f", $0.score))" }.joined(separator: ", "))" } ?? "now: —"
            Log.w("state-space", "refreshed(\(trigger)): \(g.tasks.count) tasks · \(g.windows.count) windows shown / \(g.vectorCount) stored · \(g.edges.count) edges · \(g.millis) ms · store \(g.storeLabel) · \(nowLine)")
            DispatchQueue.main.async { [weak self] in
                self?.graph = g
                NotificationCenter.default.post(name: .spaceRefreshed, object: nil)
            }
        } catch {
            Log.w("warn", "state-space refresh failed: \(error)")
        }
    }
}
