import AppKit

// ENGINE-OWNED · App shell.
// Holds ALL the pet's state (stored properties live here because Swift extensions
// can't add them) plus launch, the main window, menus, mode switching and pet selection.
// Behaviour is spread over extensions:
//   World/Platforms.swift   what the pet can stand on (windows → ledges)
//   Brain/Decide.swift      where to go next, hops and climbs
//   Brain/Desktops.swift    travelling between desktops / fullscreen apps
//   Body/Physics.swift      the 60 Hz tick: walking, falling, throws, frames
//   Body/Interaction.swift  grab / drag / release / impacts
// Design agents: nothing in Engine/ is yours. Sprites arrive via the global `pet`.

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var view: PetView!
    var statusItem: NSStatusItem!
    var prefs: PreferencesWindow?
    var modeMenu: NSMenuItem!
    var activeItem: NSMenuItem!

    /// Off = the pet disappears and the app idles; only the menu-bar icon stays so you can
    /// switch it back on. The screen saver is separate and keeps working either way.
    var petEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "petEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "petEnabled") }
    }
    func setPetEnabled(_ on: Bool) {
        petEnabled = on
        Log.w("app", on ? "pet switched on" : "pet switched off (screen saver only)")
        if on { scheduleWander(soon: true) } else { window.orderOut(nil) }
        syncMenu()
        prefs?.rebuild()
    }
    @objc func togglePet() { setPetEnabled(!petEnabled) }
    var petMenu: NSMenuItem!

    // ---- motion state (x,y = bottom-left of the sprite, AppKit screen coords) ----
    var x: CGFloat = 0, y: CGFloat = 0
    var vx: CGFloat = 0, vy: CGFloat = 0
    var targetX: CGFloat = 0
    var standing: Platform? = nil      // what we're on; nil = airborne
    var pendingJump: Int? = nil        // platform id to jump to once we reach targetX
    var pendingClimb: (id: Int, side: Int)? = nil   // window to climb once we reach its edge
    var climb: (id: Int, side: Int)? = nil          // currently climbing (side -1 = left edge, +1 = right)
    var lastFrontId: Int? = nil
    // desktops
    var petSpace: UInt64 = 0           // where the pet lives
    var userSpace: UInt64 = 0          // where you are
    var pendingSpace: UInt64? = nil    // walking to the screen edge to go here
    var pendingDir = 1                 // +1 = leave via right edge, -1 = left
    var lastSpaceChange = Date.distantPast
    var lastMoving = false             // for state sampling

    /// One word describing what the pet is doing right now (for the state log).
    var activity: String {
        switch mode {
        case .action: return "hidden"
        case .chill: return "chill"
        case .normal: break
        }
        if Spaces.available && petSpace != userSpace { return "away" }
        if held { return "held" }
        if isDizzy { return "dizzy" }
        if isPetting { return "petted" }
        if climb != nil { return "climbing" }
        if standing == nil { return "airborne" }
        return lastMoving ? "walking" : "idle"
    }

    /// Every 10 s: where exactly is the pet (debugging aid for "it's stuck" reports).
    func logPosition() {
        let on = standing?.desc ?? (climb != nil ? "climbing #\(climb!.id)" : "air")
        Log.w("pos", "x=\(Log.f(x)) y=\(Log.f(y)) v=(\(String(format: "%.1f", vx)),\(String(format: "%.1f", vy))) target=\(Log.f(targetX)) on \(on) · \(activity) · desktop \(petSpace)\(pendingJump != nil ? " pendingJump" : "")\(pendingClimb != nil ? " pendingClimb" : "")\(pendingSpace != nil ? " pendingSpace" : "")")
    }

    var nextDesktopMove = Date()       // desktop trips have their own, slower clock
    var lastIds: Set<Int> = []
    var frontChanged = false
    var selfJump = false               // airborne because of our own hop (not a throw)
    var bounce: CGFloat = 0.45         // restitution for the current flight

    // ---- interaction state ----
    var held = false
    var dragged = false
    var grabOffset = NSPoint.zero
    var lastPos = NSPoint.zero
    var velSamples: [NSPoint] = []
    var holdStart = Date()
    var lastMouse = NSEvent.mouseLocation
    var petMeter: CGFloat = 0

    // ---- timers ----
    var t: CGFloat = 0
    var tickCount = 0
    var walkFrame = 0
    var altPose = false
    var altTimer = 0
    var heartTimer = 0
    var nextWander = Date()
    var nextBlink = Date()
    var blinkUntil = Date.distantPast
    var dizzyUntil = Date.distantPast

    // ---- world ----
    var platforms: [Platform] = []
    var winRects: [(id: Int, rect: NSRect)] = []   // front-to-back, for occlusion tests
    var frontWindow: Platform? = nil
    let ownPID = ProcessInfo.processInfo.processIdentifier

    var mainScreen: NSRect { NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900) }
    var screens: [NSRect] { NSScreen.screens.map { $0.visibleFrame } }
    func screenAt(_ px: CGFloat) -> NSRect {
        let c = px + SPRITE_W / 2
        if let s = screens.first(where: { c >= $0.minX && c <= $0.maxX }) { return s }
        return screens.min(by: { abs($0.midX - c) < abs($1.midX - c) }) ?? mainScreen
    }
    var minX: CGFloat { screens.map { $0.minX }.min()! }
    var maxX: CGFloat { screens.map { $0.maxX }.max()! - WIN_W }
    var floorY: CGFloat { screenAt(x).minY }
    var ceilY: CGFloat { screenAt(x).maxY - WIN_H }
    var cx: CGFloat { x + SPRITE_W / 2 }

    var isDizzy: Bool { Date() < dizzyUntil }
    var isPetting: Bool { S.petting && petMeter > 30 && !held && !isDizzy }

    // MARK: - launch

    func applicationDidFinishLaunching(_ note: Notification) {
        // Only one pet at a time: if another copy is already running (e.g. the dev build
        // and the installed app), hand over to it and quit.
        let me = Bundle.main.bundleIdentifier ?? "com.soumil.pixelpet"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: me)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            Log.appendOnce("app", "a second copy (\(Bundle.main.bundlePath)) was launched; it is handing over to pid \(other.processIdentifier) and quitting")
            other.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        Log.start()
        Log.w("app", "pet=\(pet.name) screens=\(screens.map { "\(Log.f($0.width))x\(Log.f($0.height))" }) settings=\(String(data: (try? JSONEncoder().encode(S)) ?? Data(), encoding: .utf8) ?? "")")

        x = mainScreen.midX - SPRITE_W / 2
        y = floorY
        targetX = x

        window = NSWindow(contentRect: NSRect(x: x, y: y, width: WIN_W, height: WIN_H),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        view = PetView(frame: window.contentView!.bounds)
        view.delegate = self
        window.contentView = view
        window.orderFrontRegardless()

        petSpace = Spaces.active()
        userSpace = petSpace
        Log.w("space", Spaces.available ? "desktops: \(Spaces.list().map { "\($0.id)\($0.fullscreen ? "F" : "")" }) user on \(userSpace)" : "desktop API unavailable; pet follows you everywhere")

        buildMenu()
        buildMainMenu()
        refreshPlatforms()
        standing = floorUnder()
        scheduleWander(soon: true)
        if mode != .normal { setMode(mode) }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }

        // Opening the app shows its window (unless the user turned that off).
        if UserDefaults.standard.object(forKey: "showWindowAtLaunch") as? Bool ?? true { openMainWindow() }
    }

    /// Clicking the app in Launchpad / Finder / Dock while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Log.w("app", "reopen requested (app icon clicked) → showing window")
        openMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.w("app", "quit (normal termination: Quit menu, ⌘Q, logout, or hand-over to another copy)")
    }

    /// The app is normally invisible (menu-bar only). While its window is open it
    /// behaves like a regular app: Dock icon, ⌘-Tab, its own menu bar.
    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if prefs == nil { prefs = PreferencesWindow(app: self) }
        prefs?.show()
    }

    func mainWindowClosed() {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Minimal menu bar for when the window is open, so ⌘W / ⌘Q / ⌘, work.
    func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About PixelPet", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide PixelPet", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit PixelPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        let winItem = NSMenuItem(); main.addItem(winItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        winMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        winItem.submenu = winMenu
        NSApp.mainMenu = main
    }

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open PixelPet…", action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let come = NSMenuItem(title: "Come here", action: #selector(comeHere), keyEquivalent: "")
        come.target = self
        menu.addItem(come)
        menu.addItem(.separator())
        petMenu = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        let petSub = NSMenu()
        for (i, pp) in PETS.enumerated() {
            let it = NSMenuItem(title: pp.name, action: #selector(choosePet(_:)), keyEquivalent: "")
            it.target = self; it.tag = i
            petSub.addItem(it)
        }
        petMenu.submenu = petSub
        menu.addItem(petMenu)
        activeItem = NSMenuItem(title: "Pet active", action: #selector(togglePet), keyEquivalent: "")
        activeItem.target = self
        menu.addItem(activeItem)
        modeMenu = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in Mode.allCases {
            let it = NSMenuItem(title: m.label, action: #selector(chooseMode(_:)), keyEquivalent: "")
            it.target = self; it.tag = m.rawValue
            sub.addItem(it)
        }
        modeMenu.submenu = sub
        menu.addItem(modeMenu)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit PixelPet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc func choosePet(_ sender: NSMenuItem) {
        selectPet(sender.tag)
        prefs?.rebuild()
    }

    func syncMenu() {
        petMenu.title = "Pet: \(pet.name)"
        petMenu.submenu?.items.forEach { $0.state = $0.tag == Settings.shared.petIndex ? .on : .off }
        modeMenu.title = "Mode: \(mode.short)"
        modeMenu.submenu?.items.forEach { $0.state = $0.tag == mode.rawValue ? .on : .off }
        activeItem.state = petEnabled ? .on : .off
        statusItem.button?.title = !petEnabled ? "💤" : (mode == .chill ? "☕️" : (mode == .action ? "🫥" : "🐾"))
        statusItem.button?.toolTip = "PixelPet"
    }

    @objc func chooseMode(_ sender: NSMenuItem) { setMode(Mode(rawValue: sender.tag) ?? .normal) }

    /// Switch mode and put the pet in a sane place for it.
    func setMode(_ m: Mode) {
        let old = mode
        mode = m
        Log.w("mode", "\(old.short) → \(m.short)")
        view.hearts.removeAll()
        held = false; climb = nil; pendingJump = nil; pendingClimb = nil; pendingSpace = nil
        vx = 0; vy = 0
        switch m {
        case .chill:
            petSpace = userSpace
        case .action:
            window.orderOut(nil)
        case .normal:
            window.setContentSize(NSSize(width: WIN_W, height: WIN_H))
            view.frame = NSRect(x: 0, y: 0, width: WIN_W, height: WIN_H)
            view.palette = pet.palette
            view.overlays = true
            petSpace = userSpace
            let sc = mainScreen
            x = min(sc.maxX - SPRITE_W - 20, max(sc.minX + 20, x))
            y = sc.minY
            refreshPlatforms()
            standing = floorUnder()
            targetX = x
            window.orderFrontRegardless()
            scheduleWander(soon: true)
        }
        syncMenu()
        prefs?.rebuild()
    }

    /// Chill mode: park bottom-right with the coffee scene and do nothing else.

    @objc func openFromMenu() { openMainWindow() }
    @objc func comeHere() {
        let m = NSEvent.mouseLocation
        if petSpace != userSpace { arrive(at: userSpace, fromLeft: m.x < mainScreen.midX) }
        pendingJump = nil
        pendingClimb = nil
        pendingSpace = nil
        targetX = min(maxX, max(minX, m.x - SPRITE_W / 2))
    }

    func selectPet(_ i: Int) {
        Settings.shared.petIndex = i
        pet = PETS[i]
        view.palette = pet.palette      // the view caches the palette; refresh it or the new pet wears the old colours
        Log.w("app", "pet → \(pet.name)")
        applyPetChange()
    }

    /// Call after anything that changes the sprite's on-screen size.
    func applyPetChange() {
        if mode == .normal {
            window.setContentSize(NSSize(width: WIN_W, height: WIN_H))
            view.frame = NSRect(x: 0, y: 0, width: WIN_W, height: WIN_H)
        }
        syncMenu()
        scheduleWander(soon: true)
    }

}
