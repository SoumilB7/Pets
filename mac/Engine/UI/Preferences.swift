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

    init(app: AppDelegate) {
        self.app = app
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 660),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 600, height: 560)
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
        app?.mainWindowClosed()
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

    /// The window is the Pet page.
    func rebuild() {
        guard let w = window else { return }
        let v = buildPetPage()
        v.translatesAutoresizingMaskIntoConstraints = true
        v.autoresizingMask = [.width, .height]
        v.frame = w.contentView?.bounds ?? v.frame
        w.contentView = v
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
