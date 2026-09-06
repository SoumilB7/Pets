import AppKit

// ENGINE-OWNED. The "world state": where YOU are vs where the PET is, sampled
// once a second. Changes go to the log as [state] and every record is appended
// as one JSON line to:
//   ~/Library/Application Support/PixelPet/state.jsonl
// This is the raw material for task-aware behaviour later.

struct PetState: Equatable, Codable {
    var desktop: UInt64 = 0
    var ledgeOwner = ""          // app whose window the pet stands on, "floor", or "" while airborne
    var ledgeId = 0              // CG window number, negative = floor, 0 = none
    var activity = "idle"        // idle | walking | climbing | airborne | held | petted | dizzy | chill | hidden | away
    var mode = "Normal"
    var x = 0, y = 0
}

struct UserState: Equatable, Codable {
    var desktop: UInt64 = 0
    var app = ""
    var bundle = ""
    var title = ""
    var url = ""
    var category = "unknown"
    var idleSeconds = 0
    var work = "neutral"           // onTask | offTask | neutral | away
}

struct WorldState: Codable {
    var t: String
    var user: UserState
    var pet: PetState
    var sameDesktop: Bool
    var sameWindow: Bool         // pet stands on the window the user is working in
    var reason: String           // "change" | "heartbeat" | "start"
}

enum StateLog {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PixelPet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.jsonl")
    }()
    private static var handle: FileHandle? = {
        // keep the history bounded: roll over at ~10 MB
        if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 10_000_000 {
            let old = url.deletingLastPathComponent().appendingPathComponent("state.1.jsonl")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()

    static var lastUser = UserState()
    static var lastPet = PetState()
    static var lastWrite = Date.distantPast
    static var started = false
    static var current: WorldState? = nil

    /// Compare with the previous sample; write if anything meaningful changed
    /// (position alone doesn't count) or if 30 s passed since the last record.
    static func sample(user: UserState, pet: PetState, frontWindowId: Int?) {
        var u = user, p = pet
        let now = Date()
        var pu = lastUser, pp = lastPet
        pu.desktop = u.desktop; pp.x = p.x; pp.y = p.y; pp.desktop = p.desktop   // ignore for change detection below
        let changed = !started
            || u.app != lastUser.app || u.title != lastUser.title || u.url != lastUser.url || u.desktop != lastUser.desktop || u.work != lastUser.work
            || p.ledgeId != lastPet.ledgeId || p.activity != lastPet.activity || p.mode != lastPet.mode || p.desktop != lastPet.desktop
        let idleFlip = (u.idleSeconds >= 120) != (lastUser.idleSeconds >= 120)
        let heartbeat = now.timeIntervalSince(lastWrite) >= 30
        guard changed || heartbeat || idleFlip else { return }
        _ = pu; _ = pp
        u.category = user.category; p.activity = pet.activity
        let w = WorldState(t: iso.string(from: now), user: u, pet: p,
                           sameDesktop: u.desktop == p.desktop,
                           sameWindow: frontWindowId != nil && frontWindowId == p.ledgeId,
                           reason: !started ? "start" : (changed || idleFlip ? "change" : "heartbeat"))
        current = w
        if changed {
            let where_ = p.activity == "away" ? "away on desktop \(p.desktop)"
                : (p.ledgeId == 0 ? "in the air" : "on \(p.ledgeOwner)\(p.ledgeId > 0 ? "#\(p.ledgeId)" : "")")
            Log.w("state", "you: \(u.app.isEmpty ? "?" : u.app)\(u.title.isEmpty ? "" : " “\(u.title)”") [\(u.category)] \(u.work)\(u.idleSeconds >= 120 ? " idle \(u.idleSeconds / 60)m" : "") desktop \(u.desktop) | pet: \(where_), \(p.activity), desktop \(p.desktop)\(w.sameDesktop ? "" : " (elsewhere)")\(w.sameWindow ? " (same window as you)" : "") | mode \(p.mode)")
        }
        if let data = try? JSONEncoder().encode(w) {
            handle?.write(data)
            handle?.write("\n".data(using: .utf8)!)
        }
        lastUser = u; lastPet = p; lastWrite = now; started = true
    }
}
