import Foundation

// ENGINE-OWNED · How the work state changes the pet's behaviour.
// A Mood is the effective set of movement knobs for this moment: the user's own
// settings, bent toward "leave me alone" when they're on task and toward
// "hey, look at me" when they're drifting. Everything reads through `mood`, never `S` directly,
// for the knobs listed here.

struct Mood {
    var name: String
    var icon: String
    var pMain: Int, pOther: Int, pFloor: Int, pSpace: Int, cursorCuriosity: Int, returnToMe: Int
    var stayOnMainWindow: Bool
    var wanderScale: Double     // × decision interval
    var speedScale: Double      // × walk speed
    var hopChance: Double       // chance of a little hop at each decision

    static func neutral(_ s: PetSettings) -> Mood {
        Mood(name: "neutral", icon: "🐾", pMain: s.pMain, pOther: s.pOther, pFloor: s.pFloor, pSpace: s.pSpace,
             cursorCuriosity: s.cursorCuriosity, returnToMe: s.returnToMe, stayOnMainWindow: s.stayOnMainWindow,
             wanderScale: 1, speedScale: 1, hopChance: 0)
    }

    /// On task: get out of the way. `k` = strength 0…1.
    static func focused(_ s: PetSettings, k: Double) -> Mood {
        var m = neutral(s)
        m.name = "focused"; m.icon = "🤫"
        m.pMain = lerp(s.pMain, 0, k)
        m.pOther = lerp(s.pOther, max(s.pOther, 55), k)
        m.pSpace = lerp(s.pSpace, max(s.pSpace, 45), k)
        m.pFloor = lerp(s.pFloor, 0, k)
        m.cursorCuriosity = lerp(s.cursorCuriosity, 0, k)
        m.returnToMe = lerp(s.returnToMe, 5, k)
        m.stayOnMainWindow = k < 0.5 ? s.stayOnMainWindow : false
        m.wanderScale = 1 + 0.8 * k
        m.speedScale = 1 - 0.25 * k
        return m
    }

    /// Off task: come over and be impossible to ignore. `k` = strength 0…1.
    static func distracted(_ s: PetSettings, k: Double) -> Mood {
        var m = neutral(s)
        m.name = "distracted"; m.icon = "⚡"
        m.pMain = lerp(s.pMain, 90, k)
        m.pOther = lerp(s.pOther, 4, k)
        m.pFloor = lerp(s.pFloor, 0, k)
        m.pSpace = lerp(s.pSpace, 0, k)
        m.cursorCuriosity = lerp(s.cursorCuriosity, 75, k)
        m.returnToMe = 100
        m.stayOnMainWindow = k >= 0.5 ? true : s.stayOnMainWindow
        m.wanderScale = 1 - 0.7 * k
        m.speedScale = 1 + 0.9 * k
        m.hopChance = 0.55 * k
        return m
    }

    private static func lerp(_ a: Int, _ b: Int, _ k: Double) -> Int { Int(Double(a) + (Double(b) - Double(a)) * k) }
}
