import AppKit

// ENGINE-OWNED · The State Space page.
// Status line · "now" strip · task list with linked windows · graph · store settings.
// Redraws when the Mind posts `.spaceRefreshed`; never starts work itself.

final class StateSpacePage: NSView {
    private var handlers: [Handler] = []
    private var observer: Any?
    private var taskObserver: Any?
    private var tick: Timer?
    private let banner = NSStackView()
    private let status = NSTextField(labelWithString: "…")
    private let nowLabel = NSTextField(wrappingLabelWithString: "")
    private let listStack = NSStackView()
    private let graph = GraphView()
    private let testResult = NSTextField(wrappingLabelWithString: "")
    private var thresholdDebounce: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        observer = NotificationCenter.default.addObserver(forName: .spaceRefreshed, object: nil, queue: .main) { [weak self] _ in self?.render() }
        taskObserver = NotificationCenter.default.addObserver(forName: .tasksChanged, object: nil, queue: .main) { [weak self] _ in self?.render() }
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.renderStatus() }
        render()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) }; if let o = taskObserver { NotificationCenter.default.removeObserver(o) }; tick?.invalidate() }

    private func bind<T: NSControl>(_ c: T, _ fn: @escaping (T) -> Void) -> T {
        let h = Handler { fn($0 as! T) }; handlers.append(h); c.target = h; c.action = #selector(Handler.fire(_:)); return c
    }

    private func build() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
                                     scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor)])
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        // Auto Layout inside an NSScrollView: the document view must opt out of autoresizing
        // masks, pin to the clip view's top/leading/width, and take its height from content.
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(root)
        scroll.documentView = doc
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: clip.topAnchor), doc.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: clip.widthAnchor),
            root.topAnchor.constraint(equalTo: doc.topAnchor), root.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: doc.trailingAnchor), root.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        // status + buttons
        let head = NSStackView(); head.orientation = .horizontal; head.spacing = 10
        let title = NSTextField(labelWithString: "State Space")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        head.addArrangedSubview(title)
        head.addArrangedSubview(bind(NSButton(title: "Refresh now", target: nil, action: nil)) { _ in Mind.shared.refreshNow() })
        head.addArrangedSubview(bind(NSButton(title: "Reveal files", target: nil, action: nil)) { _ in NSWorkspace.shared.activateFileViewerSelecting([TaskStore.dir.appendingPathComponent("edges.json")]) })
        root.addArrangedSubview(head)
        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        root.addArrangedSubview(status)

        // permission banner: without Accessibility, windows are just app names and nothing links
        banner.orientation = .horizontal
        banner.spacing = 10
        banner.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor(hex: "#d98a3a").withAlphaComponent(0.18).cgColor
        banner.layer?.cornerRadius = 4
        let bText = NSTextField(wrappingLabelWithString: "Accessibility access is off, so windows can't link to notes.")
        bText.font = .systemFont(ofSize: 11)
        bText.widthAnchor.constraint(equalToConstant: 360).isActive = true
        banner.addArrangedSubview(bText)
        banner.addArrangedSubview(bind(NSButton(title: "Grant Accessibility access…", target: nil, action: nil)) { _ in Context.requestAccessibility() })
        root.addArrangedSubview(banner)

        // now strip
        let nowBox = section("Now")
        nowLabel.font = .systemFont(ofSize: 12)
        nowLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 820).isActive = true
        nowBox.addArrangedSubview(nowLabel)
        root.addArrangedSubview(nowBox)

        // graph
        let gBox = section("Map · click a note or window for details · drag notes to arrange · double-click a note to rename")
        let ctl = NSStackView(); ctl.orientation = .horizontal; ctl.spacing = 10
        let tl = NSTextField(labelWithString: "Link when ≥"); tl.font = .systemFont(ofSize: 11); tl.textColor = .secondaryLabelColor
        ctl.addArrangedSubview(tl)
        ctl.addArrangedSubview(slider(MindSettings.threshold, 0.2, 0.9, fmt: { String(format: "%.2f", $0) }) { [weak self] v in
            MindSettings.threshold = v
            self?.thresholdDebounce?.cancel()
            let w = DispatchWorkItem { Mind.shared.refreshNow() }
            self?.thresholdDebounce = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        })
        gBox.addArrangedSubview(ctl)
        graph.translatesAutoresizingMaskIntoConstraints = false
        graph.heightAnchor.constraint(equalToConstant: 520).isActive = true
        graph.widthAnchor.constraint(greaterThanOrEqualToConstant: 600).isActive = true
        gBox.addArrangedSubview(graph)
        root.addArrangedSubview(gBox)
        graph.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).isActive = true   // only after both share a tree

        // list
        let lBox = section("Links")
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 10
        lBox.addArrangedSubview(listStack)
        root.addArrangedSubview(lBox)

        // settings
        let sBox = section("Settings")
        let g = NSGridView(views: [
            [label("Vector store"), check("Mirror to Actian VectorAI DB (local store stays primary)", MindSettings.actianEnabled) { MindSettings.actianEnabled = $0; Mind.shared.configureRemote() }],
            [label("Endpoint"), textField(MindSettings.actianEndpoint, width: 320) { MindSettings.actianEndpoint = $0 }],
            [label("Token"), secureField(MindSettings.actianToken, width: 320) { MindSettings.actianToken = $0 }],
            [label(""), testRow()],
            [label("Link threshold"), slider(MindSettings.threshold, 0.2, 0.95, fmt: { String(format: "%.2f", $0) }) { MindSettings.threshold = $0 }],
            [label("Recency half-life"), slider(MindSettings.halfLifeHours, 0.5, 48, fmt: { String(format: "%.1f h", $0) }) { MindSettings.halfLifeHours = $0 }],
            [label("Full sweep every"), slider(MindSettings.sweepMinutes, 1, 30, fmt: { "\(Int($0)) min" }) { MindSettings.sweepMinutes = $0 }],
            [label("Privacy"), check("Store window titles only (no text samples)", MindSettings.titlesOnly) { MindSettings.titlesOnly = $0 }],
            [label("Exclude"), textField(MindSettings.exclusions.joined(separator: ", "), width: 420) { MindSettings.exclusions = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }],
            [label(""), hint("docker run -d --name vectorai -p 6573-6575:6573-6575 -e ACTIAN_VECTORAI_ACCEPT_EULA=YES actian/vectorai:latest")],
        ])
        g.rowSpacing = 8; g.columnSpacing = 10
        g.column(at: 0).xPlacement = .trailing
        sBox.addArrangedSubview(g)
        root.addArrangedSubview(sBox)
    }

    // MARK: small builders
    private func section(_ title: String) -> NSStackView {
        let s = NSStackView(); s.orientation = .vertical; s.alignment = .leading; s.spacing = 6
        let t = NSTextField(labelWithString: title.uppercased())
        t.font = .monospacedSystemFont(ofSize: 10, weight: .semibold); t.textColor = .tertiaryLabelColor
        s.addArrangedSubview(t)
        return s
    }
    private func label(_ s: String) -> NSTextField { let t = NSTextField(labelWithString: s); t.alignment = .right; t.textColor = .secondaryLabelColor; return t }
    private func hint(_ s: String) -> NSTextField { let t = NSTextField(wrappingLabelWithString: s); t.font = .systemFont(ofSize: 10); t.textColor = .secondaryLabelColor; t.widthAnchor.constraint(equalToConstant: 520).isActive = true; return t }
    private func check(_ t: String, _ v: Bool, on: @escaping (Bool) -> Void) -> NSButton {
        let b = bind(NSButton(checkboxWithTitle: t, target: nil, action: nil)) { on($0.state == .on) }; b.state = v ? .on : .off; return b
    }
    private func textField(_ v: String, width: CGFloat, on: @escaping (String) -> Void) -> NSTextField {
        let f = bind(NSTextField(string: v)) { on($0.stringValue) }; f.widthAnchor.constraint(equalToConstant: width).isActive = true; return f
    }
    private func secureField(_ v: String, width: CGFloat, on: @escaping (String) -> Void) -> NSSecureTextField {
        let f = bind(NSSecureTextField(string: v)) { on($0.stringValue) }; f.widthAnchor.constraint(equalToConstant: width).isActive = true; return f
    }
    private func slider(_ v: Double, _ lo: Double, _ hi: Double, fmt: @escaping (Double) -> String, on: @escaping (Double) -> Void) -> NSView {
        let box = NSStackView(); box.orientation = .horizontal; box.spacing = 8
        let out = NSTextField(labelWithString: fmt(v)); out.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let s = bind(NSSlider(value: v, minValue: lo, maxValue: hi, target: nil, action: nil)) { sl in out.stringValue = fmt(sl.doubleValue); on(sl.doubleValue) }
        s.widthAnchor.constraint(equalToConstant: 220).isActive = true
        box.addArrangedSubview(s); box.addArrangedSubview(out)
        return box
    }
    private func testRow() -> NSView {
        let box = NSStackView(); box.orientation = .horizontal; box.spacing = 8
        box.addArrangedSubview(bind(NSButton(title: "Test connection", target: nil, action: nil)) { [weak self] _ in
            self?.testResult.stringValue = "Testing…"
            DispatchQueue.global().async {
                let r = Mind.shared.testActian(endpoint: MindSettings.actianEndpoint, token: MindSettings.actianToken)
                DispatchQueue.main.async { self?.testResult.stringValue = r }
            }
        })
        testResult.font = .systemFont(ofSize: 11); testResult.textColor = .secondaryLabelColor
        testResult.widthAnchor.constraint(equalToConstant: 380).isActive = true
        box.addArrangedSubview(testResult)
        return box
    }

    // MARK: rendering
    private func renderStatus() {
        guard let g = Mind.shared.graph else {
            status.stringValue = "Starting…"; return
        }
        let ago = Int(Date().timeIntervalSince(g.updatedAt))
        let next = max(0, Int(Mind.shared.nextSweep.timeIntervalSinceNow))
        let store = Mind.shared.remote?.reachable == true ? "Actian connected (\(g.vectorCount) / 5,000)" : "local store (\(g.vectorCount) vectors)"
        status.stringValue = "Updated \(ago) s ago · next pass \(next / 60):\(String(format: "%02d", next % 60)) · \(store) · \(g.edges.count) links"
    }

    func render() {
        renderStatus()
        banner.isHidden = Context.accessibilityGranted
        let live = TaskStore.shared.open
        guard let g = Mind.shared.graph else {
            graph.set(SpaceGraph(updatedAt: Date(), trigger: "none", tasks: [], windows: [], edges: [], now: nil, storeLabel: "local", vectorCount: 0, millis: 0), tasks: live)
            return
        }
        let work = (NSApp.delegate as? AppDelegate)?.work.summary ?? ""
        if let n = g.now {
            let close = n.tasks.filter { $0.score >= Float(MindSettings.threshold) }
            let line = close.isEmpty
                ? "\(n.app) · \(n.title.isEmpty ? "(no title)" : n.title)  →  no note close enough" + (n.tasks.first.map { " (closest: \($0.title) \(String(format: "%.2f", $0.score)))" } ?? "")
                : "\(n.app) · \(n.title.isEmpty ? "(no title)" : n.title)  →  " + close.map { "\($0.title) (\(String(format: "%.2f", $0.score)))" }.joined(separator: "  ·  ")
            nowLabel.stringValue = line + (work.isEmpty ? "" : "\n" + work)
        } else {
            nowLabel.stringValue = work.isEmpty ? "…" : work
        }
        graph.set(g, tasks: live)   // live tasks: a note just added shows before its links arrive

        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let byId = Dictionary(uniqueKeysWithValues: g.windows.map { ($0.id, $0) })
        if g.tasks.isEmpty {
            listStack.addArrangedSubview(NSTextField(labelWithString: "No notes yet."))
        }
        for t in g.tasks {
            let box = NSStackView(); box.orientation = .vertical; box.alignment = .leading; box.spacing = 3
            let head = NSTextField(labelWithString: "■ \(t.title)")
            head.font = .systemFont(ofSize: 13, weight: .semibold)
            head.textColor = NSColor(hex: TaskStore.colors[min(t.color, TaskStore.colors.count - 1)].hex).blended(withFraction: 0.55, of: .labelColor) ?? .labelColor
            box.addArrangedSubview(head)
            let es = g.edges.filter { $0.taskId == t.id }.sorted { $0.weight > $1.weight }.prefix(8)
            if es.isEmpty {
                let none = NSTextField(labelWithString: "   no links yet"); none.textColor = .tertiaryLabelColor; none.font = .systemFont(ofSize: 11)
                box.addArrangedSubview(none)
            }
            for e in es {
                guard let w = byId[e.windowId] else { continue }
                let row = NSStackView(); row.orientation = .horizontal; row.spacing = 8
                let icon = NSImageView(image: AppIcons.icon(bundle: w.bundle))
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
                row.addArrangedSubview(icon)
                let bar = NSView(); bar.wantsLayer = true
                bar.layer?.backgroundColor = NSColor(hex: "#1f8e91").withAlphaComponent(e.weak == true ? 0.3 : 0.8).cgColor
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.widthAnchor.constraint(equalToConstant: CGFloat(4 + e.weight * 90)).isActive = true
                bar.heightAnchor.constraint(equalToConstant: 6).isActive = true
                row.addArrangedSubview(bar)
                let l = NSTextField(labelWithString: "\(String(format: "%.2f", e.score))\(e.weak == true ? " (closest, below threshold)" : "")  \(w.app) · \(w.title.isEmpty ? (w.url.isEmpty ? "(no title)" : w.url) : String(w.title.prefix(70)))  · \(TasksPage.rel(w.lastSeen))")
                l.font = .systemFont(ofSize: 11)
                l.lineBreakMode = .byTruncatingTail
                l.toolTip = w.url.isEmpty ? w.title : w.url
                row.addArrangedSubview(l)
                box.addArrangedSubview(row)
            }
            listStack.addArrangedSubview(box)
        }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

// MARK: - App icons

enum AppIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(bundle: String) -> NSImage {
        if let i = cache[bundle] { return i }
        var img: NSImage
        if !bundle.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        img.size = NSSize(width: 64, height: 64)
        cache[bundle] = img
        return img
    }
}

// MARK: - Graph

/// The map. Sticky notes (tasks) sit wherever you put them; windows are app icons that
/// settle near the notes they relate to. A pad of blank notes on the right is where new
/// notes come from; a bin under it is where they go.
final class GraphView: NSView {
    private struct N {
        var id: String; var label: String; var task: Bool; var color: NSColor; var bundle: String
        var x: CGFloat; var y: CGFloat; var fixed: Bool; var degree: Int; var linked: Bool
    }
    private var nodes: [N] = []
    private var edges: [Edge] = []
    private var selected: String?
    private var dragging: (id: String, moved: Bool, dx: CGFloat, dy: CGFloat)?
    private var editor: NSTextField?
    private var editorHandler: Handler?
    private var lastGraph: SpaceGraph?
    private var lastTasks: [Task] = []
    private var lastSize = NSSize.zero
    private var phase: CGFloat = 0
    private var anim: Timer?
    private var nowId: String?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        anim?.invalidate()
        guard window != nil else { return }
        anim = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.edges.isEmpty || self.nowId != nil else { return }
            self.phase += 0.012
            if self.phase > 1 { self.phase -= 1 }
            self.needsDisplay = true
        }
    }

    static let noteSize = NSSize(width: 74, height: 50)
    var canvasWidth: CGFloat { max(300, bounds.width) }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: data → nodes

    func set(_ g: SpaceGraph, tasks: [Task]) {
        lastGraph = g; lastTasks = tasks
        let w = canvasWidth, h = max(bounds.height, 300)
        let previous = Dictionary(uniqueKeysWithValues: nodes.filter { !$0.task }.map { ($0.id, ($0.x, $0.y)) })
        var ns: [N] = []
        for (i, t) in tasks.enumerated() {
            // default spot: a loose grid on the left half; the user's own placement wins
            let col = i % 3, row = i / 3
            let x = t.mapX.map { CGFloat($0) * w } ?? (90 + CGFloat(col) * 150)
            let y = t.mapY.map { CGFloat($0) * h } ?? (70 + CGFloat(row) * 120)
            ns.append(N(id: t.id, label: t.title, task: true, color: NSColor(hex: TaskStore.colors[min(t.color, TaskStore.colors.count - 1)].hex), bundle: "",
                        x: x, y: y, fixed: true, degree: g.edges.filter { $0.taskId == t.id }.count, linked: true))
        }
        let linked = Set(g.edges.map { $0.windowId })
        var seed: UInt64 = 42
        func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((seed >> 33) % 10000) / 10000 }
        for wn in g.windows {
            let deg = g.edges.filter { $0.windowId == wn.id }.count
            let p = previous[wn.id] ?? (w * (0.55 + rnd() * 0.4), h * (0.15 + rnd() * 0.7))
            ns.append(N(id: wn.id, label: wn.title.isEmpty ? wn.app : wn.title, task: false, color: .clear, bundle: wn.bundle,
                        x: p.0, y: p.1, fixed: false, degree: deg, linked: linked.contains(wn.id)))
        }
        nodes = ns
        edges = g.edges
        nowId = g.now?.windowId
        relax(steps: previous.isEmpty ? 220 : 70)
        needsDisplay = true
    }

    /// Point on the cubic used for a link, t in 0…1.
    private func curvePoint(_ A: NSPoint, _ B: NSPoint, _ t: CGFloat) -> NSPoint {
        let my = (A.y + B.y) / 2 - 24
        let c1 = NSPoint(x: A.x, y: my), c2 = NSPoint(x: B.x, y: my)
        let u = 1 - t
        let x = u*u*u*A.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*B.x
        let y = u*u*u*A.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*B.y
        return NSPoint(x: x, y: y)
    }

    /// Spring layout for the window icons; notes never move on their own.
    private func relax(steps: Int) {
        guard nodes.count > 1 else { return }
        let w = canvasWidth, h = max(bounds.height, 300)
        let idx = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })
        for _ in 0..<steps {
            var fx = [CGFloat](repeating: 0, count: nodes.count), fy = fx
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    var dx = nodes[j].x - nodes[i].x, dy = nodes[j].y - nodes[i].y
                    var d2 = dx * dx + dy * dy
                    if d2 < 1 { dx = 0.5; dy = 0.5; d2 = 0.5 }
                    let pad: CGFloat = (nodes[i].task || nodes[j].task) ? 3200 : 2000   // notes are big: keep icons off them
                    let f = pad / d2
                    let d = sqrt(d2)
                    fx[i] -= dx / d * f; fy[i] -= dy / d * f; fx[j] += dx / d * f; fy[j] += dy / d * f
                }
            }
            for e in edges {
                guard let a = idx[e.taskId], let b = idx[e.windowId] else { continue }
                let dx = nodes[b].x - nodes[a].x, dy = nodes[b].y - nodes[a].y
                let d = max(1, sqrt(dx * dx + dy * dy))
                let want: CGFloat = 90 + (1 - CGFloat(e.weight)) * 110
                let f = (d - want) * 0.035
                fx[b] -= dx / d * f; fy[b] -= dy / d * f
            }
            for i in 0..<nodes.count where !nodes[i].fixed {
                let tx: CGFloat = nodes[i].linked ? w * 0.5 : w * 0.8     // unlinked icons drift to the right edge, out of the way
                fx[i] += (tx - nodes[i].x) * 0.003; fy[i] += (h / 2 - nodes[i].y) * 0.002
                nodes[i].x = min(w - 26, max(26, nodes[i].x + max(-6, min(6, fx[i]))))
                nodes[i].y = min(h - 30, max(26, nodes[i].y + max(-6, min(6, fy[i]))))
            }
        }
    }

    // MARK: geometry

    private func noteRect(_ n: N) -> NSRect {
        NSRect(x: n.x - GraphView.noteSize.width / 2, y: n.y - GraphView.noteSize.height / 2, width: GraphView.noteSize.width, height: GraphView.noteSize.height)
    }
    private func tilt(_ id: String) -> CGFloat {
        let h = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff }
        return (CGFloat(h % 100) / 100 - 0.5) * 4 * .pi / 180     // ±2°
    }

    private func hit(_ p: NSPoint) -> N? {
        if let n = nodes.first(where: { $0.task && noteRect($0).insetBy(dx: -4, dy: -4).contains(p) }) { return n }
        return nodes.filter { !$0.task }.min { hypot($0.x - p.x, $0.y - p.y) < hypot($1.x - p.x, $1.y - p.y) }
            .flatMap { hypot($0.x - p.x, $0.y - p.y) < 22 ? $0 : nil }
    }

    // MARK: editing

    private func beginEdit(_ n: N) {
        editor?.removeFromSuperview()
        let r = noteRect(n)
        let f = NSTextField(frame: NSRect(x: r.minX - 30, y: r.minY + 10, width: r.width + 60, height: 24))
        f.stringValue = n.label
        f.font = .systemFont(ofSize: 11, weight: .medium)
        f.isBordered = true; f.bezelStyle = .roundedBezel
        f.backgroundColor = n.color
        f.textColor = .black
        f.placeholderString = "Write the task… ⏎"
        let h = Handler { [weak self, weak f] _ in
            guard let f = f else { return }
            let t = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            f.removeFromSuperview(); self?.editor = nil
            if t.isEmpty { TaskStore.shared.delete(n.id) }              // an empty note goes back to the pad
            else if var task = TaskStore.shared.task(n.id) { task.title = t; TaskStore.shared.update(task) }
        }
        editorHandler = h
        f.target = h; f.action = #selector(Handler.fire(_:))
        addSubview(f)
        editor = f
        window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
    }

    override func cancelOperation(_ sender: Any?) { editor?.removeFromSuperview(); editor = nil }

    // MARK: mouse

    override func mouseDown(with event: NSEvent) {
        if editor != nil { window?.makeFirstResponder(self) }   // commit whatever was being typed
        let p = convert(event.locationInWindow, from: nil)
        let n = hit(p)
        selected = n?.id
        if let n = n, n.task {
            if event.clickCount == 2 { beginEdit(n); return }
            dragging = (n.id, false, n.x - p.x, n.y - p.y)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let d = dragging, let i = nodes.firstIndex(where: { $0.id == d.id }) else { return }
        nodes[i].x = min(bounds.width - 20, max(20, p.x + d.dx))
        nodes[i].y = min(bounds.height - 20, max(20, p.y + d.dy))
        dragging = (d.id, true, d.dx, d.dy)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        _ = convert(event.locationInWindow, from: nil)
        guard let d = dragging else { return }
        dragging = nil
        if d.moved {
            if let n = nodes.first(where: { $0.id == d.id }) {
                TaskStore.shared.place(d.id, x: Double(min(canvasWidth - 70, n.x) / max(1, canvasWidth)), y: Double(n.y / max(1, bounds.height)))
                relax(steps: 40)
            }
            needsDisplay = true
        }
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        if let g = lastGraph { set(g, tasks: lastTasks) }
    }

    // MARK: drawing

    override func draw(_ dirtyRect: NSRect) {
        // canvas: soft paper with a faint dot grid
        NSColor.textBackgroundColor.withAlphaComponent(0.55).setFill()
        bounds.fill()
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        var gy: CGFloat = 12
        while gy < bounds.height { var gx: CGFloat = 12; while gx < canvasWidth { NSRect(x: gx - 0.75, y: gy - 0.75, width: 1.5, height: 1.5).fill(); gx += 24 }; gy += 24 }
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 1; border.stroke()

        let idx = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })

        // 1) highlighter clouds: each note's territory, in the note's colour, wrapping its windows
        for n in nodes where n.task {
            let mine = edges.filter { $0.taskId == n.id && $0.weak != true }
            guard !mine.isEmpty else { continue }
            let dim = !(selected == nil || selected == n.id)
            // just a whisper of the note's colour under each linked window; no beams, no halo on the note
            let tint = n.color.withAlphaComponent(dim ? 0.02 : 0.07)
            tint.setFill()
            for e in mine {
                guard let b = idx[e.windowId] else { continue }
                let rr: CGFloat = 26 + CGFloat(e.weight) * 10
                NSBezierPath(ovalIn: NSRect(x: nodes[b].x - rr, y: nodes[b].y - rr, width: rr * 2, height: rr * 2)).fill()
            }
        }

        // 2) links: gradient curves from the note's colour to teal, with flowing dots
        for e in edges {
            guard let a = idx[e.taskId], let b = idx[e.windowId] else { continue }
            let hi = selected == nil || selected == e.taskId || selected == e.windowId
            let A = NSPoint(x: nodes[a].x, y: nodes[a].y), B = NSPoint(x: nodes[b].x, y: nodes[b].y)
            let from = nodes[a].color.blended(withFraction: 0.5, of: NSColor(hex: "#b8712e")) ?? nodes[a].color
            let to = NSColor(hex: "#1f8e91")
            if e.weak == true {
                // closest window but below the threshold: a quiet dashed hint
                let path = NSBezierPath()
                path.move(to: A); path.curve(to: B, controlPoint1: NSPoint(x: A.x, y: (A.y + B.y) / 2 - 24), controlPoint2: NSPoint(x: B.x, y: (A.y + B.y) / 2 - 24))
                path.setLineDash([4, 5], count: 2, phase: 0); path.lineWidth = 1.2
                NSColor.secondaryLabelColor.withAlphaComponent(hi ? 0.5 : 0.12).setStroke(); path.stroke()
                if selected == e.taskId || selected == e.windowId {
                    let mid = curvePoint(A, B, 0.5)
                    NSAttributedString(string: String(format: "%.2f · below %.2f", e.score, MindSettings.threshold), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]).draw(at: NSPoint(x: mid.x - 30, y: mid.y - 14))
                }
                continue
            }
            let width = 1.2 + CGFloat(e.weight) * 3.5
            let alpha: CGFloat = hi ? 0.3 + CGFloat(e.weight) * 0.5 : 0.06
            let segs = 24
            var prev = curvePoint(A, B, 0)
            for i in 1...segs {
                let t = CGFloat(i) / CGFloat(segs)
                let pt = curvePoint(A, B, t)
                (from.blended(withFraction: t, of: to) ?? to).withAlphaComponent(alpha).setStroke()
                let seg = NSBezierPath(); seg.move(to: prev); seg.line(to: pt); seg.lineWidth = width; seg.lineCapStyle = .round; seg.stroke()
                prev = pt
            }
            if hi {
                // travelling sparks show the connection is live; faster when stronger
                let count = 2 + Int(e.weight * 3)
                for k in 0..<count {
                    let t = (phase * (0.6 + CGFloat(e.weight)) + CGFloat(k) / CGFloat(count)).truncatingRemainder(dividingBy: 1)
                    let pt = curvePoint(A, B, t)
                    NSColor.white.withAlphaComponent(0.9).setFill()
                    NSBezierPath(ovalIn: NSRect(x: pt.x - 2.2, y: pt.y - 2.2, width: 4.4, height: 4.4)).fill()
                    to.withAlphaComponent(0.6).setFill()
                    NSBezierPath(ovalIn: NSRect(x: pt.x - 1.2, y: pt.y - 1.2, width: 2.4, height: 2.4)).fill()
                }
            }
            if selected == e.taskId || selected == e.windowId {
                let mid = curvePoint(A, B, 0.5)
                let s = NSAttributedString(string: String(format: "%.2f", e.score), attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold), .foregroundColor: to])
                s.draw(at: NSPoint(x: mid.x - 10, y: mid.y - 14))
            }
        }
        // window icons
        for n in nodes where !n.task {
            let dim = !(selected == nil || selected == n.id || edges.contains { $0.windowId == n.id && $0.taskId == selected })
            let strong = edges.contains { $0.windowId == n.id && $0.weak != true }
            let size: CGFloat = strong ? 28 : (n.linked ? 22 : 16)
            let alpha: CGFloat = dim ? 0.25 : (strong ? 1 : (n.linked ? 0.8 : 0.45))
            let r = NSRect(x: n.x - size / 2, y: n.y - size / 2, width: size, height: size)
            let owner = edges.filter({ $0.windowId == n.id && $0.weak != true }).max(by: { $0.weight < $1.weight }).flatMap { e in idx[e.taskId].map { nodes[$0].color } }
            if strong && !dim {
                // glow in the colour of the strongest note it belongs to
                if let best = edges.filter({ $0.windowId == n.id }).max(by: { $0.weight < $1.weight }), let a = idx[best.taskId] {
                    let glow = nodes[a].color.blended(withFraction: 0.3, of: .systemOrange) ?? nodes[a].color
                    for (k, al) in [(1.7, 0.05), (1.35, 0.08), (1.15, 0.11)] {
                        glow.withAlphaComponent(CGFloat(al)).setFill()
                        NSBezierPath(ovalIn: NSRect(x: n.x - size * CGFloat(k) / 2, y: n.y - size * CGFloat(k) / 2, width: size * CGFloat(k), height: size * CGFloat(k))).fill()
                    }
                }
            }
            if nowId == n.id {
                // the window you are in right now: a breathing teal ring
                let pulse = 1 + 0.12 * sin(phase * 2 * .pi)
                let rr = size * 0.8 * pulse
                NSColor(hex: "#1f8e91").withAlphaComponent(0.85).setStroke()
                let ring = NSBezierPath(ovalIn: NSRect(x: n.x - rr, y: n.y - rr, width: rr * 2, height: rr * 2)); ring.lineWidth = 2; ring.stroke()
                let tag = NSAttributedString(string: "you are here", attributes: [.font: NSFont.systemFont(ofSize: 8, weight: .semibold), .foregroundColor: NSColor(hex: "#1f8e91")])
                tag.draw(at: NSPoint(x: n.x - 28, y: n.y - rr - 12))
            }
            if strong, let oc = owner {
                // connected: a coloured card in the note's colour with the app icon on it
                let card = r.insetBy(dx: -6, dy: -6)
                NSColor.black.withAlphaComponent(0.2 * alpha).setFill()
                NSBezierPath(roundedRect: card.offsetBy(dx: 1, dy: 2), xRadius: 9, yRadius: 9).fill()
                oc.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: card, xRadius: 9, yRadius: 9).fill()
                NSColor.white.withAlphaComponent(0.35 * alpha).setStroke()
                let rim = NSBezierPath(roundedRect: card.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8); rim.lineWidth = 1; rim.stroke()
                AppIcons.icon(bundle: n.bundle).draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            } else {
                // not connected: a plain grey disc, icon muted
                NSColor.labelColor.withAlphaComponent(0.08 * alpha * 2).setFill()
                NSBezierPath(ovalIn: r.insetBy(dx: -4, dy: -4)).fill()
                AppIcons.icon(bundle: n.bundle).draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha * 0.8, respectFlipped: true, hints: nil)
            }
            if selected == n.id { NSColor(hex: "#1f8e91").setStroke(); let ring = NSBezierPath(roundedRect: r.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10); ring.lineWidth = 2; ring.stroke() }
            if n.linked || selected == n.id {
                let ps = NSMutableParagraphStyle(); ps.alignment = .center; ps.lineBreakMode = .byTruncatingTail
                let s = NSAttributedString(string: String(n.label.prefix(30)), attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.labelColor.withAlphaComponent(alpha), .paragraphStyle: ps])
                s.draw(in: NSRect(x: n.x - 60, y: r.maxY + 3, width: 120, height: 12))
            }
        }
        // sticky notes
        for n in nodes where n.task { drawNote(n, dim: !(selected == nil || selected == n.id)) }
        // detail card for whatever is selected
        if let sel = selected, let n = nodes.first(where: { $0.id == sel }) { drawCard(for: n) }
        if nodes.filter({ $0.task }).isEmpty {
            let s = NSAttributedString(string: "Take a note on the Tasks page.", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            s.draw(at: NSPoint(x: 16, y: 16))
        }
    }

    private func drawNote(_ n: N, dim: Bool) {
        let footer = n.degree == 0 ? "" : "\(n.degree)"
        drawSticky(center: NSPoint(x: n.x, y: n.y), color: n.color, text: n.label, tilt: tilt(n.id), dim: dim, footer: footer, selected: selected == n.id)
    }

    /// A card next to the selected node with everything worth knowing about it.
    private func drawCard(for n: N) {
        var title = n.label, lines: [String] = []
        if n.task, let task = TaskStore.shared.task(n.id) {
            title = task.title
            if !task.text.isEmpty { lines.append(task.text) }
            lines.append("\(task.column) · added \(TasksPage.rel(task.createdAt))")
            let mine = edges.filter { $0.taskId == n.id }.sorted { $0.score > $1.score }
            if mine.isEmpty { lines.append("No windows linked yet.") }
            for e in mine.prefix(5) {
                if let b = nodes.first(where: { $0.id == e.windowId }) {
                    lines.append("\(e.weak == true ? "◌" : "●") \(String(format: "%.2f", e.score))  \(b.label.prefix(34))")
                }
            }
        } else if let g = lastGraph, let w = g.windows.first(where: { $0.id == n.id }) {
            title = w.title.isEmpty ? w.app : w.title
            lines.append(w.app + (w.url.isEmpty ? "" : " · " + w.url))
            lines.append("\(w.category) · seen \(w.seenCount)× · last \(TasksPage.rel(w.lastSeen))")
            let mine = edges.filter { $0.windowId == n.id }.sorted { $0.score > $1.score }
            for e in mine.prefix(4) {
                if let a = nodes.first(where: { $0.id == e.taskId }) { lines.append("\(e.weak == true ? "◌" : "●") \(String(format: "%.2f", e.score))  \(a.label.prefix(34))") }
            }
        }
        let width: CGFloat = 250
        let tf = NSFont.systemFont(ofSize: 12, weight: .semibold), bf = NSFont.systemFont(ofSize: 10.5)
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byWordWrapping
        let titleStr = NSAttributedString(string: title, attributes: [.font: tf, .foregroundColor: NSColor.labelColor, .paragraphStyle: ps])
        let th = min(48, ceil(titleStr.boundingRect(with: NSSize(width: width - 24, height: 60), options: [.usesLineFragmentOrigin]).height))
        let body = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [.font: bf, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: ps])
        let bh = ceil(body.boundingRect(with: NSSize(width: width - 24, height: 160), options: [.usesLineFragmentOrigin]).height)
        let height = 14 + th + 6 + bh + 12
        var x = n.x + (n.task ? GraphView.noteSize.width / 2 : 22) + 12, y = n.y - height / 2
        if x + width > bounds.width - 8 { x = n.x - (n.task ? GraphView.noteSize.width / 2 : 22) - 12 - width }
        x = max(8, x); y = min(bounds.height - height - 8, max(8, y))
        let r = NSRect(x: x, y: y, width: width, height: height)
        NSColor.black.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: 3), xRadius: 8, yRadius: 8).fill()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        (n.task ? n.color : NSColor(hex: "#1f8e91")).setFill()
        NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.minY, width: 5, height: r.height), xRadius: 2.5, yRadius: 2.5).fill()
        NSColor.separatorColor.setStroke()
        let rim = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8); rim.lineWidth = 1; rim.stroke()
        titleStr.draw(in: NSRect(x: r.minX + 14, y: r.minY + 12, width: width - 24, height: th + 2))
        body.draw(in: NSRect(x: r.minX + 14, y: r.minY + 12 + th + 6, width: width - 24, height: bh + 2))
    }

    private func drawSticky(center: NSPoint, color: NSColor, text: String, tilt: CGFloat, dim: Bool, footer: String, selected: Bool = false) {
        let sz = GraphView.noteSize
        NSGraphicsContext.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: center.x, yBy: center.y)
        t.rotate(byRadians: tilt)
        t.concat()
        let r = NSRect(x: -sz.width / 2, y: -sz.height / 2, width: sz.width, height: sz.height)
        NSColor.black.withAlphaComponent(dim ? 0.06 : 0.22).setFill()
        r.offsetBy(dx: 2, dy: 3).fill()
        color.withAlphaComponent(dim ? 0.45 : 1).setFill()
        r.fill()
        // the curled top strip of glue
        NSColor.white.withAlphaComponent(0.35).setFill()
        NSRect(x: r.minX, y: r.minY, width: r.width, height: 9).fill()
        if selected { NSColor(hex: "#1f8e91").setStroke(); let p = NSBezierPath(rect: r); p.lineWidth = 2; p.stroke() }
        let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingTail
        let body = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                                                                 .foregroundColor: NSColor.black.withAlphaComponent(dim ? 0.45 : 0.9), .paragraphStyle: ps])
        body.draw(in: NSRect(x: r.minX + 6, y: r.minY + 11, width: r.width - 12, height: 26))
        if !footer.isEmpty {
            let f = NSAttributedString(string: footer, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold), .foregroundColor: NSColor.black.withAlphaComponent(dim ? 0.3 : 0.55)])
            f.draw(at: NSPoint(x: r.maxX - 6 - f.size().width, y: r.maxY - 12))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

}
