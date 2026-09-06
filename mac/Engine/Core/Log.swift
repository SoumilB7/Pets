import Foundation

// ENGINE-OWNED · Event log.
//   ~/Library/Logs/PixelPet.log        this run (fresh at every launch)
//   ~/Library/Logs/PixelPet.prev.log   the run before
// Never per-frame. One line per event, "HH:mm:ss.SSS [tag] message".
//
// Tags:
//   app      launch, pet change, quit
//   settings a setting changed (old → new)
//   mode     Normal / Chill / Action switches
//   space    desktops: where you are, where the pet is, trips
//   scan     the set of visible windows changed (with covered ledges marked)
//   front    your main window changed
//   context  what you're doing (app, title, url, category)
//   state    you-vs-pet state changed (also saved to state.jsonl)
//   decide   a wander decision and the weights behind it
//   travel   hop / climb / walk-to-take-off plans
//   arrive   landed / climbed onto something
//   fall     lost the ledge (walked off, window vanished)
//   throw    you threw it
//   impact   hard hit → dizzy
//   pos      position heartbeat every 10 s (x, y, ledge, activity)
//   work     on task / off task / neutral transitions (with the note and score)
//   mood     the pet's reaction to a work-state change
//   warn     something unexpected but survivable
//   crash    fatal signal / uncaught exception (last line of a bad run)

enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("PixelPet.log")
    }()
    static let prevURL = url.deletingLastPathComponent().appendingPathComponent("PixelPet.prev.log")

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "logEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "logEnabled") }
    }
    private static var handle: FileHandle?
    /// Raw descriptor for the crash handler (write(2) is async-signal-safe; FileHandle isn't).
    static var fd: Int32 { handle?.fileDescriptor ?? -1 }
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()

    static func w(_ tag: String, _ msg: String) {
        guard enabled, let h = handle else { return }
        h.write("\(fmt.string(from: Date())) [\(tag)] \(msg)\n".data(using: .utf8)!)
    }

    /// Append one line to the existing log WITHOUT rotating (used by a second copy that is about to quit).
    static func appendOnce(_ tag: String, _ msg: String) {
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        h.seekToEndOfFile()
        h.write("\(fmt.string(from: Date())) [\(tag)] \(msg)\n".data(using: .utf8)!)
        try? h.close()
    }

    /// Called once at launch: previous log becomes .prev, a new one starts with a header.
    static func start() {
        let fm = FileManager.default
        try? fm.removeItem(at: prevURL)
        try? fm.moveItem(at: url, to: prevURL)
        fm.createFile(atPath: url.path, contents: nil)
        handle = try? FileHandle(forWritingTo: url)
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        w("app", "PixelPet \(v) started · pid \(ProcessInfo.processInfo.processIdentifier) · \(os) · \(Bundle.main.bundlePath)")
        installCrashHandlers()
    }

    /// Make sure every run ends with a line saying how it ended.
    static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { e in
            Log.w("crash", "uncaught exception \(e.name.rawValue): \(e.reason ?? "") \(e.callStackSymbols.prefix(8))")
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE] {
            signal(sig) { s in
                let msg = "[crash] fatal signal \(s) — see ~/Library/Logs/DiagnosticReports\n"
                msg.withCString { p in _ = write(Log.fd, p, strlen(p)) }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
        signal(SIGTERM) { s in
            let msg = "[app] SIGTERM (killed by another process, e.g. pkill / a new install)\n"
            msg.withCString { p in _ = write(Log.fd, p, strlen(p)) }
            signal(s, SIG_DFL)
            raise(s)
        }
    }

    static func f(_ v: CGFloat) -> String { String(format: "%.0f", v) }
}
