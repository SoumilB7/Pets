import AppKit

// DESIGN-OWNED. The list of pets shown in the menu, in this order.
// Add a new pet: create Design/Pets/<Name>.swift defining `let <NAME> = PetSprite(...)`,
// then append it here. The engine saves the chosen index into this array.
let PETS: [PetSprite] = [DOG, CAT, PERRY, DRAGON, CLAWD]

// =====================================================================
//  Extra animations (DESIGN-OWNED, opt-in for the engine).
//  See mac/DESIGN_REQUESTS.md for how the engine is asked to use these.
//  Every frame is a full sprite (body + legs rows); frames inside one
//  AnimSeq share a width, but a sequence may be wider than the pet.
//  Palette chars not in the pet's own palette live in `PetExtras.palette`.
// =====================================================================
struct AnimSeq {
    let frames: [[String]]
    let fps: Double
    let loop: Bool
    var cols: Int { frames.first?.first?.count ?? 0 }
    var rows: Int { frames.first?.count ?? 0 }
}

struct PetExtras {
    /// Extra colours used only by these frames; merge over the pet's palette.
    let palette: [Character: NSColor]
    /// Facing the user. Frame 0 is neutral; later frames are blink / glance.
    let front: AnimSeq?
    /// Self-propelled flight (wings flapping). Faces right, mirrored to face left.
    let fly: AnimSeq?
    /// Pet-specific "leave the screen" sequence. Last frame should be empty
    /// (all '.'), so the pet is gone when it ends.
    let exit: AnimSeq?
    /// Reverse of `exit`: arrive on screen. Frame 0 empty, last = standing.
    let enter: AnimSeq?
    /// Common mode shared by every pet: coffee on a beach bench.
    let coffee: AnimSeq?
}

/// Pet name → extras. Engine: `PET_EXTRAS[pet.name]`.
let PET_EXTRAS: [String: PetExtras] = [
    DOG.name: DOG_EXTRAS,
    CAT.name: CAT_EXTRAS,
    PERRY.name: PERRY_EXTRAS,
    DRAGON.name: DRAGON_EXTRAS,
    CLAWD.name: CLAWD_EXTRAS,
]

/// Validate an AnimSeq the same way PetSprite.validate() does.
func validateExtras(_ name: String, _ x: PetExtras, base: PetSprite) -> [String] {
    var out: [String] = []
    let pal = base.palette.merging(x.palette) { _, b in b }
    for (label, seq) in [("front", x.front), ("fly", x.fly), ("exit", x.exit), ("enter", x.enter), ("coffee", x.coffee)] {
        guard let s = seq else { continue }
        for (fi, f) in s.frames.enumerated() {
            if f.count != s.rows { out.append("\(name).\(label)[\(fi)]: \(f.count) rows, expected \(s.rows)") }
            for (ri, r) in f.enumerated() where r.count != s.cols {
                out.append("\(name).\(label)[\(fi)] row \(ri): \(r.count) wide, expected \(s.cols)")
            }
            for r in f { for c in r where c != "." && pal[c] == nil {
                out.append("\(name).\(label)[\(fi)]: char '\(c)' missing from palette"); break } }
        }
    }
    return out
}

// ---------------------------------------------------------------------
//  Shared scenery for the coffee mode. Pets are drawn on top of this
//  with `onBench`, so the bench, sand and mug look identical for every pet.
//  Chars: '=' bench slat, '|' bench leg, 's' sand, 'm' mug, 'c' coffee,
//         '~' steam, 'S' sea.   All pets' extras palettes include SCENE_PALETTE.
// ---------------------------------------------------------------------
let SCENE_PALETTE: [Character: NSColor] = [
    "=": rgb(0.78, 0.60, 0.38), "|": rgb(0.52, 0.36, 0.22), "s": rgb(0.96, 0.88, 0.66),
    "m": rgb(0.97, 0.97, 0.95), "c": rgb(0.42, 0.26, 0.14), "~": rgb(0.85, 0.85, 0.85),
    "S": rgb(0.45, 0.75, 0.90), "T": rgb(0.55, 0.36, 0.22), "u": rgb(0.98, 0.80, 0.30),
]

/// 26 wide × 18 tall. Rows 0-11 open air above the bench, 12-13 slats, 14-15 legs, 16-17 sand.
let BENCH_SCENE: [String] = [
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..........................",
    "..======================..",
    "..======================..",
    "...||..............||.....",
    "...||..............||.....",
    "ssssssssssssssssssssssssss",
    "ssssssssssssssssssssssssss",
]

/// Stamp `sprite` rows onto `base` at (x, y). '.' in the sprite is transparent.
func stamp(_ base: [String], _ sprite: [String], x: Int, y: Int) -> [String] {
    var out = base.map { Array($0) }
    for (r, row) in sprite.enumerated() {
        for (c, ch) in row.enumerated() where ch != "." {
            let yy = y + r, xx = x + c
            if yy >= 0, yy < out.count, xx >= 0, xx < out[yy].count { out[yy][xx] = ch }
        }
    }
    return out.map { String($0) }
}

/// Overlay `sprite` rows onto the bench scene at (x, y).
func onBench(_ sprite: [String], x: Int, y: Int) -> [String] { stamp(BENCH_SCENE, sprite, x: x, y: y) }
