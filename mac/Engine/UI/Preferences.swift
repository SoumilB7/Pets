import AppKit
import ServiceManagement

// ENGINE-OWNED. The Preferences window. Built in code, no storyboard.
// One tab per settings group; every control writes straight into `S`
// (the current pet's settings) and the engine picks the change up next frame.

/// Retains a closure so plain AppKit target/action can call into Swift closures.
final class Handler: NSObject {
    let fn: (NSControl) -> Void
    init(_ fn: @escaping (NSControl) -> Void) { self.fn = fn }
    @objc func fire(_ c: NSControl) { fn(c) }
}

/// Static preview of the current pet (base pose, standing legs) at a chosen pixel size.
final class SpritePreview: NSView {
    var scale: CGFloat = 5
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: CGFloat(pet.cols) * scale, height: CGFloat(pet.rows) * scale) }
    override func draw(_ dirtyRect: NSRect) {
        for (y, row) in (pet.body + pet.legsStand).enumerated() {
            for (x, c) in row.enumerated() {
                guard let color = pet.palette[c] else { continue }
                color.setFill()
                NSRect(x: CGFloat(x) * scale, y: CGFloat(y) * scale, width: scale, height: scale).fill()
            }
        }
    }
}

final class PreferencesWindow: NSWindowController, NSWindowDelegate {
    var handlers: [Handler] = []
    weak var app: AppDelegate?
    enum Page: Int, CaseIterable { case pet, tasks, space
        var title: String { ["Pet", "Tasks", "State Space"][rawValue] }
        var icon: String { ["🐾", "🗒️", "🕸️"][rawValue] }
    }
    var page: Page = Page(rawValue: UserDefaults.standard.integer(forKey: "ui.page")) ?? .pet
    private var contentHost = NSView()
    private var sideButtons: [NSButton] = []
    private var tasksPage: TasksPage?
    private var spacePage: StateSpacePage?
    var contextLabel: NSTextField?
    var contextTimer: Timer?

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 820, height: 560)
        w.title = "PixelPet"
        // follow the user: appear on whatever desktop / fullscreen app is active when opened
        w.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        w.center()
        super.init(window: w)
        w.delegate = self
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        rebuild()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        contextTimer?.invalidate()
        contextTimer = nil
        app?.mainWindowClosed()
    }

    func startContextTimer() {
        contextTimer?.invalidate()
        contextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            let c = Context.current
            self?.contextLabel?.stringValue = """
            App: \(c.app)  (\(c.bundle))
            Category: \(c.category.rawValue)
            Window: \(c.title.isEmpty ? "—" : c.title)
            Document: \(c.document.isEmpty ? "—" : c.document)
            URL: \(c.url.isEmpty ? "—" : c.url)
            Idle: \(c.idleSeconds) s
            Windows the pet can see: \(c.windowCount)
            Accessibility access: \(Context.accessibilityGranted ? "granted" : "not granted (titles / URLs unavailable)")

            You are on desktop: \(StateLog.current?.user.desktop ?? 0)
            Pet is on desktop:  \(StateLog.current?.pet.desktop ?? 0)\((StateLog.current?.sameDesktop ?? true) ? "" : "  (elsewhere)")
            Pet stands on:      \(StateLog.current.map { $0.pet.ledgeId == 0 ? "nothing (in the air)" : "\($0.pet.ledgeOwner)\($0.pet.ledgeId > 0 ? " #\($0.pet.ledgeId)" : "")" } ?? "—")\((StateLog.current?.sameWindow ?? false) ? "  (your window)" : "")
            Pet activity:       \(StateLog.current?.pet.activity ?? "—")
            """
        }
        contextTimer?.fire()
    }

    // MARK: building blocks

    func bind<T: NSControl>(_ c: T, _ fn: @escaping (T) -> Void) -> T {
        let h = Handler { fn($0 as! T) }
        handlers.append(h)
        c.target = h
        c.action = #selector(Handler.fire(_:))
        return c
    }

    func label(_ s: String) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.alignment = .right
        return t
    }

    /// Slider with a live value readout. `fmt` turns the value into text.
    func slider(_ value: Double, _ lo: Double, _ hi: Double, fmt: @escaping (Double) -> String,
                onChange: @escaping (Double) -> Void) -> NSView {
        let box = NSStackView()
        box.orientation = .horizontal
        box.spacing = 8
        let readout = NSTextField(labelWithString: fmt(value))
        readout.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let s = bind(NSSlider(value: value, minValue: lo, maxValue: hi, target: nil, action: nil)) { sl in
            readout.stringValue = fmt(sl.doubleValue)
            onChange(sl.doubleValue)
        }
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: 220).isActive = true
        box.addArrangedSubview(s)
        box.addArrangedSubview(readout)
        return box
    }

    func check(_ title: String, _ value: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
        let b = bind(NSButton(checkboxWithTitle: title, target: nil, action: nil)) { onChange($0.state == .on) }
        b.state = value ? .on : .off
        return b
    }

    func popup(_ items: [String], _ selected: Int, onChange: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = bind(NSPopUpButton(frame: .zero, pullsDown: false)) { onChange($0.indexOfSelectedItem) }
        p.addItems(withTitles: items)
        p.selectItem(at: selected)
        return p
    }

    func grid(_ rows: [(String, NSView)]) -> NSView {
        let g = NSGridView(views: rows.map { [label($0.0), $0.1] })
        g.rowSpacing = 10
        g.columnSpacing = 12
        g.column(at: 0).xPlacement = .trailing
        g.column(at: 0).width = 150
        let wrap = NSView()
        wrap.addSubview(g)
        g.translatesAutoresizingMaskIntoConstraints = false
        g.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 18).isActive = true
        g.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 12).isActive = true
        return wrap
    }

    func pct(_ v: Double) -> String { "\(Int(v))%" }
    func num(_ v: Double, _ unit: String = "") -> String { String(format: "%.1f%@", v, unit) }

    // MARK: layout

    /// The whole window: a sidebar on the left, the chosen page on the right.
    func rebuild() {
        guard let w = window else { return }
        let split = NSStackView()
        split.orientation = .horizontal
        split.alignment = .top
        split.spacing = 0
        split.translatesAutoresizingMaskIntoConstraints = false

        let side = NSStackView()
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 4
        side.edgeInsets = NSEdgeInsets(top: 18, left: 12, bottom: 12, right: 12)
        side.wantsLayer = true
        side.layer?.backgroundColor = NSColor.windowBackgroundColor.blended(withFraction: 0.06, of: .labelColor)?.cgColor
        side.translatesAutoresizingMaskIntoConstraints = false
        side.widthAnchor.constraint(equalToConstant: 168).isActive = true
        let brand = NSTextField(labelWithString: "PixelPet")
        brand.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
        side.addArrangedSubview(brand)
        side.setCustomSpacing(14, after: brand)
        sideButtons = []
        for p in Page.allCases {
            let b = bind(NSButton(title: "\(p.icon)  \(p.title)", target: nil, action: nil)) { [weak self] _ in self?.show(p) }
            b.bezelStyle = .inline
            b.alignment = .left
            b.font = .systemFont(ofSize: 13, weight: p == page ? .semibold : .regular)
            b.widthAnchor.constraint(equalToConstant: 144).isActive = true
            b.tag = p.rawValue
            side.addArrangedSubview(b)
            sideButtons.append(b)
        }
        let spacer = NSView(); spacer.translatesAutoresizingMaskIntoConstraints = false
        side.addArrangedSubview(spacer)
        let ver = NSTextField(labelWithString: "v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
        ver.font = .monospacedSystemFont(ofSize: 10, weight: .regular); ver.textColor = .tertiaryLabelColor
        side.addArrangedSubview(ver)
        split.addArrangedSubview(side)

        contentHost = NSView()
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(contentHost)

        w.contentView = split
        side.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        contentHost.heightAnchor.constraint(equalTo: split.heightAnchor).isActive = true
        show(page)
    }

    func show(_ p: Page) {
        page = p
        for b in sideButtons { b.font = .systemFont(ofSize: 13, weight: b.tag == p.rawValue ? .semibold : .regular) }
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let v: NSView
        switch p {
        case .pet: v = buildPetPage()
        case .tasks: tasksPage = tasksPage ?? TasksPage(frame: .zero); tasksPage!.build(); v = tasksPage!
        case .space: spacePage = spacePage ?? StateSpacePage(frame: .zero); spacePage!.render(); v = spacePage!
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: contentHost.topAnchor), v.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
                                     v.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor), v.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor)])
        UserDefaults.standard.set(p.rawValue, forKey: "ui.page")   // remember only once the page built fine
        Log.w("app", "window page → \(p.title)")
    }

    /// The Pet page: everything that used to be the whole preferences window.
    func buildPetPage() -> NSView {
        handlers.removeAll(where: { _ in false })
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        // ---- header: preview + which pet these settings belong to ----
        let head = NSStackView()
        head.orientation = .horizontal
        head.spacing = 10
        let preview = SpritePreview()
        preview.widthAnchor.constraint(equalToConstant: 96).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 72).isActive = true
        head.addArrangedSubview(preview)
        head.addArrangedSubview(NSTextField(labelWithString: "Pet:"))
        head.addArrangedSubview(popup(PETS.map { $0.name }, Settings.shared.petIndex) { [weak self] i in
            self?.app?.selectPet(i)
            self?.rebuild()
        })
        let copy = bind(NSButton(title: "Copy to all pets", target: nil, action: nil)) { [weak self] _ in
            Settings.shared.copyToAll(from: pet.name); self?.rebuild()
        }
        let reset = bind(NSButton(title: "Reset this pet", target: nil, action: nil)) { [weak self] _ in
            Settings.shared.reset(pet.name); self?.app?.applyPetChange(); self?.rebuild()
        }
        head.addArrangedSubview(copy)
        head.addArrangedSubview(reset)
        root.addArrangedSubview(head)

        let modeRow = NSStackView()
        modeRow.orientation = .horizontal
        modeRow.spacing = 10
        modeRow.addArrangedSubview(NSTextField(labelWithString: "Mode:"))
        modeRow.addArrangedSubview(popup(Mode.allCases.map { $0.label }, mode.rawValue) { [weak self] i in
            self?.app?.setMode(Mode(rawValue: i) ?? .normal)
        })
        root.addArrangedSubview(modeRow)

        let note = NSTextField(wrappingLabelWithString: "Every setting below is saved separately for each pet.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        root.addArrangedSubview(note)

        // ---- tabs ----
        let tabs = NSTabView()
        let s = S

        let look = grid([
            ("Pixel size", slider(s.pixelSize, 3, 8, fmt: { self.num($0, " pt") }) { v in S.pixelSize = v; self.app?.applyPetChange() }),
            ("Walk speed", slider(s.walkSpeed, 0.5, 4, fmt: { self.num($0) }) { v in S.walkSpeed = v }),
            ("Jump height", slider(s.jumpHeight, 40, 400, fmt: { "\(Int($0)) pt" }) { v in S.jumpHeight = v }),
            ("Decide every", slider(s.wanderMin, 0.5, 15, fmt: { self.num($0, " s") }) { v in S.wanderMin = v; if S.wanderMax < v { S.wanderMax = v } }),
            ("…up to", slider(s.wanderMax, 1, 30, fmt: { self.num($0, " s") }) { v in S.wanderMax = max(v, S.wanderMin) }),
        ])
        addTab(tabs, "General", look)

        let zone = grid([
            ("Hang out", popup(HomeZone.allCases.map { $0.label }, s.homeZone.rawValue) { S.homeZone = HomeZone(rawValue: $0) ?? .anywhere }),
            ("Stay in that zone", slider(Double(s.stayHome), 0, 100, fmt: pct) { v in S.stayHome = Int(v) }),
            ("", check("Avoid the middle of the screen", s.avoidCenter) { S.avoidCenter = $0 }),
        ])
        addTab(tabs, "Zone", zone)

        let move = grid([
            ("", check("Walk on top of windows", s.walkOnWindows) { S.walkOnWindows = $0 }),
            ("", check("Always stay with me (my window and my desktop)", s.stayOnMainWindow) { S.stayOnMainWindow = $0; self.app?.syncMenu() }),
            ("", check("May wander to other desktops / fullscreen apps" + (Spaces.available ? "" : " (unavailable on this Mac)"), s.roamDesktops) { S.roamDesktops = $0 }),
            ("Go to another desktop", slider(Double(s.pSpace), 0, 90, fmt: pct) { v in S.pSpace = Int(v) }),
            ("Come find me after I switch", slider(Double(s.returnToMe), 0, 100, fmt: pct) { v in S.returnToMe = Int(v) }),
            ("Desktop trips at most every", slider(s.desktopEvery, 5, 180, fmt: { "\(Int($0)) s" }) { v in S.desktopEvery = v }),
            ("Go to main window", slider(Double(s.pMain), 0, 90, fmt: pct) { v in S.pMain = Int(v); if S.pMain + S.pOther > 90 { S.pOther = 90 - S.pMain } }),
            ("Go to other windows", slider(Double(s.pOther), 0, 90, fmt: pct) { v in S.pOther = Int(v); if S.pMain + S.pOther > 90 { S.pMain = 90 - S.pOther } }),
            ("Hop to the floor", slider(Double(s.pFloor), 0, 50, fmt: pct) { v in S.pFloor = Int(v) }),
            ("Approach my cursor", slider(Double(s.cursorCuriosity), 0, 100, fmt: pct) { v in S.cursorCuriosity = Int(v) }),
        ])
        addTab(tabs, "Movement", move)

        let workTab = grid([
            ("", check("Change behaviour with my work state (from the State Space)", s.workAware) { S.workAware = $0 }),
            ("On task: get out of the way", slider(s.focusStrength, 0, 1, fmt: { "\(Int($0 * 100))%" }) { v in S.focusStrength = v }),
            ("Off task: get hyperactive", slider(s.hyperStrength, 0, 1, fmt: { "\(Int($0 * 100))%" }) { v in S.hyperStrength = v }),
            ("React after", slider(s.distractDwell, 5, 300, fmt: { "\(Int($0)) s off task" }) { v in S.distractDwell = v }),
            ("Check my work state every", slider(s.workCheckSeconds, 1, 30, fmt: { "\(Int($0)) s" }) { v in S.workCheckSeconds = v }),
            ("Off task means", check("media & social windows (YouTube, Twitter…) and windows far from every note", !s.strictOffTask) { S.strictOffTask = !$0 }),
            ("", check("Strict: any window not linked to a note", s.strictOffTask) { S.strictOffTask = $0 }),
        ])
        addTab(tabs, "Work", workTab)

        let phys = grid([
            ("Gravity", slider(s.gravity, 0.2, 1.5, fmt: { self.num($0) }) { v in S.gravity = v }),
            ("Bounciness", slider(s.bounciness, 0, 0.95, fmt: { self.num($0) }) { v in S.bounciness = v }),
            ("", check("Holding longer before a throw makes it bouncier", s.holdAffectsBounce) { S.holdAffectsBounce = $0 }),
            ("", check("Can be dragged and thrown", s.throwable) { S.throwable = $0 }),
            ("", check("Tap makes it hop", s.clickHop) { S.clickHop = $0 }),
        ])
        addTab(tabs, "Physics", phys)

        let anim = grid([
            ("Dizzy (X eyes + stars)", popup(DizzyMode.allCases.map { $0.label }, s.dizzyMode.rawValue) { S.dizzyMode = DizzyMode(rawValue: $0) ?? .ceilingOnly }),
            ("Dizzy for", slider(s.dizzySeconds, 0.5, 6, fmt: { self.num($0, " s") }) { v in S.dizzySeconds = v }),
            ("", check("Petting (rub with the cursor)", s.petting) { S.petting = $0 }),
            ("", check("Hearts while petting", s.hearts) { S.hearts = $0 }),
            ("", check("Blinking", s.blink) { S.blink = $0 }),
            ("", check("Idle bob", s.idleBob) { S.idleBob = $0 }),
            ("", check("Idle pose animation (tail wag, glance…)", s.idlePose) { S.idlePose = $0 }),
            ("", check("Walking legs", s.walkAnim) { S.walkAnim = $0 }),
            ("", check("Airborne pose (flap, splay)", s.airPose) { S.airPose = $0 }),
        ])
        addTab(tabs, "Animations", anim)

        let ctxText = NSTextField(wrappingLabelWithString: "…")
        ctxText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        ctxText.widthAnchor.constraint(equalToConstant: 400).isActive = true
        contextLabel = ctxText
        let ctxNote = NSTextField(wrappingLabelWithString: "What the pet knows about the window you're in right now. Window titles, documents and page URLs need Accessibility access (System Settings → Privacy & Security → Accessibility). Nothing leaves your Mac; changes are written to the log.")
        ctxNote.textColor = .secondaryLabelColor
        ctxNote.font = .systemFont(ofSize: 11)
        ctxNote.widthAnchor.constraint(equalToConstant: 380).isActive = true
        let ctxTab = grid([
            ("Now", ctxText),
            ("", bind(NSButton(title: Context.accessibilityGranted ? "Accessibility access granted ✓" : "Grant Accessibility access…", target: nil, action: nil)) { _ in Context.requestAccessibility() }),
            ("State history", bind(NSButton(title: "Reveal state.jsonl", target: nil, action: nil)) { _ in NSWorkspace.shared.activateFileViewerSelecting([StateLog.url]) }),
            ("", ctxNote),
        ])
        addTab(tabs, "Context", ctxTab)
        startContextTimer()

        let loginOn = SMAppService.mainApp.status == .enabled
        let showAtLaunch = UserDefaults.standard.object(forKey: "showWindowAtLaunch") as? Bool ?? true
        let appTab = grid([
            ("", check("Show this window when PixelPet opens", showAtLaunch) { UserDefaults.standard.set($0, forKey: "showWindowAtLaunch") }),
            ("", check("Launch PixelPet at login", loginOn) { on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { NSLog("login item: \(error)") }
            }),
            ("", check("Write a log of what the pet sees and decides", Log.enabled) { Log.enabled = $0 }),
            ("Log file", bind(NSButton(title: "Open PixelPet.log", target: nil, action: nil)) { _ in NSWorkspace.shared.open(Log.url) }),
            ("", bind(NSButton(title: "Reveal in Finder", target: nil, action: nil)) { _ in NSWorkspace.shared.activateFileViewerSelecting([Log.url]) }),
            ("", bind(NSButton(title: "About PixelPet", target: nil, action: nil)) { _ in NSApp.orderFrontStandardAboutPanel(nil) }),
            ("", bind(NSButton(title: "Quit PixelPet", target: nil, action: nil)) { _ in NSApp.terminate(nil) }),
        ])
        addTab(tabs, "App", appTab)

        root.addArrangedSubview(tabs)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.heightAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        root.translatesAutoresizingMaskIntoConstraints = false
        return root
    }

    func addTab(_ tabs: NSTabView, _ title: String, _ view: NSView) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        tabs.addTabViewItem(item)
    }
}
