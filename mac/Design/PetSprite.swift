import AppKit

// =====================================================================
//  PetSprite — THE CONTRACT between Design and Engine.
//
//  DESIGN agents: create values of this type (see Design/Pets/*.swift).
//  ENGINE agents: consume it. Nobody edits this file without telling
//  the other side, because both compartments compile against it.
//
//  Grid rules (checked by `validate()` and by `tools/preview.py`):
//    • Every row string in body / bodyAlt / legs* must have the same
//      width (`cols`). 18 is the house standard; wider is allowed.
//    • body and bodyAlt must have the same number of rows.
//    • legsStand / legsWalk / legsAir must have the same number of rows.
//    • '.' is transparent. Any other character must exist in `palette`.
//    • 'e' marks EYE pixels. When the pet blinks the engine replaces
//      every 'e' with `bodyChar`, so 'e' must be used only for eyes.
//    • The sprite FACES RIGHT. The engine mirrors it to face left.
//    • Row 0 is the top of the pet. The last leg row is the feet, and the
//      feet are what stand on the floor / window ledge.
// =====================================================================
struct PetSprite {
    /// Shown in the menu bar picker.
    let name: String

    /// Character → colour. '.' is never looked up.
    let palette: [Character: NSColor]

    /// Base pose (everything above the legs).
    let body: [String]

    /// Alternate pose. The engine flips between body/bodyAlt:
    ///   • slowly (~0.75 s) when idle   → tail wag, glance, breathing…
    ///   • quickly (~0.12 s) when airborne → wing flap, flailing…
    ///   • never while walking.
    /// Use the same rows as `body` if the pet has no idle animation.
    let bodyAlt: [String]

    /// Leg rows appended under `body` for each state.
    let legsStand: [String]   // standing still
    let legsWalk: [String]    // alternated with legsStand every ~0.13 s while walking
    let legsAir: [String]     // in the air or being held

    /// Grid positions (col, row) of eye centres, in body coordinates.
    /// The engine draws a "^" (happy) or "X" (dizzy) centred on each.
    let eyes: [(col: Int, row: Int)]

    /// Colour used for the happy / dizzy eye overlays.
    let eyeColor: NSColor

    /// Palette character drawn over 'e' pixels when the eyes are shut.
    let bodyChar: Character

    var cols: Int { body.first?.count ?? 0 }
    var rows: Int { body.count + legsStand.count }

    /// Returns a list of problems; empty means the sprite is well-formed.
    func validate() -> [String] {
        var out: [String] = []
        let all = body + bodyAlt + legsStand + legsWalk + legsAir
        for (i, r) in all.enumerated() where r.count != cols {
            out.append("\(name): row \(i) is \(r.count) wide, expected \(cols)")
        }
        if body.count != bodyAlt.count { out.append("\(name): body/bodyAlt row count differs") }
        if legsStand.count != legsWalk.count || legsStand.count != legsAir.count {
            out.append("\(name): legs* row counts differ")
        }
        for r in all { for c in r where c != "." && palette[c] == nil {
            out.append("\(name): char '\(c)' missing from palette"); break } }
        if palette[bodyChar] == nil { out.append("\(name): bodyChar not in palette") }
        for e in eyes where e.row < 0 || e.row >= body.count || e.col < 0 || e.col >= cols {
            out.append("\(name): eye \(e) outside the body grid")
        }
        return out
    }
}

/// Convenience for palettes: rgb(0…1, 0…1, 0…1)
func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }

/// Shared dark outline colour most pets use.
let OUT = rgb(0.23, 0.16, 0.23)
