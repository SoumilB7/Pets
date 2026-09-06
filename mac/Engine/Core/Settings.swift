import AppKit

// ENGINE-OWNED. Every tunable the user can change, stored PER PET.
// `S` is the live settings for the currently selected pet. Read it anywhere.
// Add a field here + a control in Preferences.swift and the engine can use it.

enum DizzyMode: Int, Codable, CaseIterable {
    case never, ceilingOnly, anyHardHit
    var label: String {
        switch self {
        case .never: return "Never"
        case .ceilingOnly: return "Only when it hits the ceiling"
        case .anyHardHit: return "Any hard impact"
        }
    }
}

/// Where the pet prefers to hang out so it stays out of your way.
enum HomeZone: Int, Codable, CaseIterable {
    case anywhere, bottomEdge, bottomLeft, bottomRight, leftEdge, rightEdge, sideEdges
    var label: String {
        switch self {
        case .anywhere: return "Anywhere"
        case .bottomEdge: return "Bottom edge"
        case .bottomLeft: return "Bottom-left corner"
        case .bottomRight: return "Bottom-right corner"
        case .leftEdge: return "Left edge"
        case .rightEdge: return "Right edge"
        case .sideEdges: return "Left or right edge"
        }
    }
    /// Horizontal band of the screen (fractions of width) the zone covers.
    var xBand: ClosedRange<CGFloat> {
        switch self {
        case .anywhere, .bottomEdge: return 0...1
        case .bottomLeft, .leftEdge: return 0...0.28
        case .bottomRight, .rightEdge: return 0.72...1
        case .sideEdges: return Bool.random() ? 0...0.28 : 0.72...1
        }
    }
    /// How high up the screen (fraction of height) ledges may be inside the zone.
    var maxHeight: CGFloat {
        switch self {
        case .anywhere, .leftEdge, .rightEdge, .sideEdges: return 1
        case .bottomEdge, .bottomLeft, .bottomRight: return 0.35
        }
    }
}

struct PetSettings: Codable {
    // where it hangs out
    var homeZone: HomeZone = .anywhere
    var stayHome: Int = 80             // % of decisions that stay inside the home zone
    var avoidCenter: Bool = true       // steer clear of the middle 40% of the screen

    // look
    var pixelSize: Double = 4          // points per sprite pixel (3…8)

    // movement
    var walkSpeed: Double = 1.4        // points per frame
    var jumpHeight: Double = 160       // max lift when hopping between ledges, points
    var wanderMin: Double = 3          // seconds between decisions
    var wanderMax: Double = 8
    var walkOnWindows: Bool = true     // use window top edges as ledges
    var stayOnMainWindow: Bool = false // always stay with me: my window AND my desktop
    var roamDesktops: Bool = true      // may leave for other desktops / fullscreen apps
    var pSpace: Int = 25               // % chance a decision is "go to another desktop"
    var returnToMe: Int = 60           // % chance, each time the desktop timer fires, to come find me
    var desktopEvery: Double = 20      // seconds between desktop trips (leave or come back), at least
    var pMain: Int = 35                // % chance to head for the frontmost window
    var pOther: Int = 40               // % chance to head for some other window
    var pFloor: Int = 10               // % chance to hop down to the floor
    var cursorCuriosity: Int = 15      // % of "wander along" moves that approach the cursor

    // physics
    var gravity: Double = 0.6
    var bounciness: Double = 0.45      // restitution used for throws (and hops)
    var holdAffectsBounce: Bool = true // holding longer before a throw = bouncier
    var throwable: Bool = true         // drag & fling
    var clickHop: Bool = true          // tap = little hop

    // animations & reactions
    var dizzyMode: DizzyMode = .ceilingOnly
    var dizzySeconds: Double = 2.2
    var petting: Bool = true           // rub with the cursor → happy eyes
    var hearts: Bool = true            // …and floating hearts
    var blink: Bool = true
    var idleBob: Bool = true
    var idlePose: Bool = true          // body/bodyAlt swap while idle
    var walkAnim: Bool = true          // leg alternation while walking
    var airPose: Bool = true           // legsAir + fast bodyAlt swap while airborne

    static func decode(_ data: Data) -> PetSettings? {
        // tolerate missing keys from older versions by overlaying onto defaults
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(PetSettings())) as? [String: Any]
        else { return nil }
        for (k, v) in raw { base[k] = v }
        guard let merged = try? JSONSerialization.data(withJSONObject: base) else { return nil }
        return try? JSONDecoder().decode(PetSettings.self, from: merged)
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private var perPet: [String: PetSettings] = [:]

    init() {
        if let blob = d.dictionary(forKey: "petSettings") as? [String: Data] {
            for (k, v) in blob { if let s = PetSettings.decode(v) { perPet[k] = s } }
        }
    }

    var petIndex: Int {
        get { max(0, min(PETS.count - 1, d.integer(forKey: "petIndex"))) }
        set { d.set(newValue, forKey: "petIndex") }
    }

    func settings(for name: String) -> PetSettings { perPet[name] ?? PetSettings() }

    func set(_ s: PetSettings, for name: String) {
        let old = perPet[name] ?? PetSettings()
        perPet[name] = s
        save()
        // log exactly which fields changed
        if let a = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any],
           let b = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] {
            let diffs = b.keys.sorted().compactMap { k -> String? in
                let av = a[k].map { "\($0)" } ?? "nil", bv = b[k].map { "\($0)" } ?? "nil"
                return av == bv ? nil : "\(k): \(av) → \(bv)"
            }
            if !diffs.isEmpty { Log.w("settings", "\(name): " + diffs.joined(separator: ", ")) }
        }
    }

    func reset(_ name: String) { perPet[name] = nil; save() }

    func copyToAll(from name: String) {
        let s = settings(for: name)
        for p in PETS { perPet[p.name] = s }
        save()
    }

    private func save() {
        var blob: [String: Data] = [:]
        for (k, v) in perPet { if let data = try? JSONEncoder().encode(v) { blob[k] = data } }
        d.set(blob, forKey: "petSettings")
    }
}

/// App-wide mode (not per pet).
enum Mode: Int, CaseIterable {
    case normal, chill, action
    var label: String {
        switch self {
        case .normal: return "Normal"
        case .chill: return "Chill (coffee break, bottom right)"
        case .action: return "Action (pet hidden)"
        }
    }
    var short: String { ["Normal", "Chill", "Action"][rawValue] }
}
var mode: Mode {
    get { Mode(rawValue: UserDefaults.standard.integer(forKey: "mode")) ?? .normal }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
}

/// Live settings for the current pet.
var S: PetSettings {
    get { Settings.shared.settings(for: pet.name) }
    set { Settings.shared.set(newValue, for: pet.name) }
}
