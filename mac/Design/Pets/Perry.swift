import AppKit

// DESIGN-OWNED. Pixel art for "Perry the Platypus".
// Rules live in Design/PetSprite.swift. Preview with:  python3 tools/preview.py Perry --all
// Register new pets in Design/Registry.swift.
//
// Teal squat body, wide orange bill, brown fedora with a black band, flat paddle
// tail behind, orange webbed feet. Eyes sit on top of the head like the real thing.

let PERRY = PetSprite(
    name: "Perry the Platypus",
    palette: ["o": OUT, "b": rgb(0.12, 0.64, 0.65), "d": rgb(0.07, 0.46, 0.48), "h": rgb(0.45, 0.29, 0.15),
              "H": rgb(0.12, 0.10, 0.10), "n": rgb(0.98, 0.66, 0.16), "N": rgb(0.85, 0.50, 0.10),
              "e": rgb(0.08, 0.06, 0.08), "w": NSColor.white],
    body: [
        "........ohhhhhho..",
        "........ohhhhhho..",
        "........oHHHHHHo..",
        ".......ohhhhhhhhho",
        "........obwebbbo..",
        "........obbbbbonnn",
        "oo.....obbbbbbonnn",
        "oddo..obbbbbbbbNNN",
        "odddoooobbbbbbbbo.",
        ".odddbbbbbbbbbbbo.",
        "..obbbbbbbbbbbbo..",
    ],
    bodyAlt: [  // tail slap: paddle tail lifts
        "........ohhhhhho..",
        "........ohhhhhho..",
        "........oHHHHHHo..",
        ".......ohhhhhhhhho",
        "oo......obwebbbo..",
        "oddo....obbbbbonnn",
        "odddo..obbbbbbonnn",
        ".odddoobbbbbbbbNNN",
        "..odddbbbbbbbbbbo.",
        "...obbbbbbbbbbbbo.",
        "..obbbbbbbbbbbbo..",
    ],
    legsStand: ["....onno..onno....", "....onno..onno....", "...onnnno.onnnno.."],
    legsWalk:  ["...onno....onno...", "...onno....onno...", "..onnnno..onnnno.."],
    legsAir:   ["...onno....onno...", "..onnno....onnno..", ".onnnno....onnnno."],
    eyes: [(11, 4)], eyeColor: rgb(0.08, 0.06, 0.08), bodyChar: "b")

// ---- extras (engine hooks requested in DESIGN_REQUESTS.md) ----

/// Perry looking straight at you: both eyes on top of the head, bill front and centre.
private let PERRY_FRONT_BASE: [String] = [
    ".....ohhhhhhho....",
    ".....ohhhhhhho....",
    ".....oHHHHHHHo....",
    "...ohhhhhhhhhhho..",
    "....obwebbbwebo...",
    "....obbbbbbbbbo...",
    "...oonnnnnnnnnoo..",
    "..odonnnnnnnnnodo.",
    "..odoNNNNNNNNNodo.",
    "...oobbbbbbbbboo..",
    "....obbbbbbbbbo...",
    "....onno..onno....",
    "....onno..onno....",
    "...onnnno.onnnno..",
]
private func perryFront(eyes: String) -> [String] {
    var f = PERRY_FRONT_BASE; f[4] = "....o" + eyes + "o..."; return f
}

/// Standing frame shifted down by `dy` rows over a floor hatch (Perry's secret tube).
private let PERRY_STAND: [String] = PERRY.body + PERRY.legsStand
private func perryDrop(_ dy: Int, hatch: [String]) -> [String] {
    var f = hatch
    for (r, row) in PERRY_STAND.enumerated() where r + dy < f.count {
        var line = Array(f[r + dy])
        for (c, ch) in row.enumerated() where ch != "." { line[c] = ch }
        f[r + dy] = String(line)
    }
    return f
}
private let EMPTY18 = Array(repeating: String(repeating: ".", count: 18), count: 14)
private let HATCH_OPEN: [String] = EMPTY18.enumerated().map { i, r in
    i >= 12 ? ".kkkkkkkkkkkkkkkk." : r }
private let HATCH_CLOSING: [String] = EMPTY18.enumerated().map { i, r in
    i == 13 ? ".oooooooooooooooo." : r }

/// Chill mode: Perry off duty. The fedora sits on the bench beside him, and without it
/// he is just a platypus, so he drinks like one: bill straight into the mug.
/// Sitting sprite is 16 wide × 15 tall; the last three rows dangle over the slats.
private let PERRY_CHILL_HOLD: [String] = [
    "................",
    "................",
    "................",
    ".......ooooo....",
    "......obwebbbo..",
    "......obbbbbonnn",
    "oo...obbbbbbonnn",
    "oddo.obbbbbbbNNN",
    "odddobbbbbbbbbo.",
    ".odddbbbbbbbbbo.",
    "..obbbbbbbbbbmcm",
    "...oobbbbbbbbmmm",
    "....onno.onnomm.",
    "....onno.onno...",
    "...onnnnoonnnno.",
]
private let PERRY_CHILL_DIP: [String] = [   // bill in the mug
    "................",
    "................",
    "................",
    ".......ooooo....",
    "......obwebbbo..",
    "......obbbbbonnn",
    "oo...obbbbbbommm",
    "oddo.obbbbbbbmmm",
    "odddobbbbbbbbmm.",
    ".odddbbbbbbbbbo.",
    "..obbbbbbbbbbbo.",
    "...oobbbbbbbbbo.",
    "....onno.onno...",
    "....onno.onno...",
    "...onnnnoonnnno.",
]
private let PERRY_CHILL_GULP: [String] = PERRY_CHILL_DIP.map {   // eyes shut, savouring
    $0.replacingOccurrences(of: "e", with: "b") }

/// The fedora, brim down, resting on the bench.
private let PERRY_HAT_ASIDE: [String] = [
    ".ohhhhhho..",
    ".oHHHHHHo..",
    "ohhhhhhhhho",
]
private func perryCoffee(_ pet: [String], steam: [(Int, Int)]) -> [String] {
    var f = onBench(pet, x: 9, y: 0)
    f = stamp(f, PERRY_HAT_ASIDE, x: 1, y: 9)
    for (x, y) in steam { var l = Array(f[y]); if l[x] == "." { l[x] = "~" }; f[y] = String(l) }
    return f
}

let PERRY_EXTRAS = PetExtras(
    palette: SCENE_PALETTE.merging(["k": rgb(0.10, 0.09, 0.12)]) { a, _ in a },
    front: AnimSeq(frames: [
        perryFront(eyes: "bwebbbweb"),   // neutral
        perryFront(eyes: "bbbbbbbbb"),   // blink
        perryFront(eyes: "bewbbbewb"),   // glance the other way
    ], fps: 2, loop: true),
    fly: nil,
    exit: AnimSeq(frames: [
        PERRY_STAND,
        perryDrop(0, hatch: HATCH_OPEN),
        perryDrop(4, hatch: HATCH_OPEN),
        perryDrop(8, hatch: HATCH_OPEN),
        perryDrop(12, hatch: HATCH_OPEN),
        HATCH_OPEN,
        HATCH_CLOSING,
        EMPTY18,
    ], fps: 8, loop: false),
    enter: AnimSeq(frames: [
        EMPTY18,
        HATCH_CLOSING,
        HATCH_OPEN,
        perryDrop(12, hatch: HATCH_OPEN),
        perryDrop(8, hatch: HATCH_OPEN),
        perryDrop(4, hatch: HATCH_OPEN),
        perryDrop(0, hatch: HATCH_OPEN),
        PERRY_STAND,
    ], fps: 8, loop: false),
    coffee: AnimSeq(frames: [
        perryCoffee(PERRY_CHILL_HOLD, steam: [(23, 9), (24, 8)]),
        perryCoffee(PERRY_CHILL_HOLD, steam: [(24, 9), (23, 8)]),
        perryCoffee(PERRY_CHILL_HOLD, steam: [(23, 9), (24, 8)]),
        perryCoffee(PERRY_CHILL_DIP,  steam: []),
        perryCoffee(PERRY_CHILL_GULP, steam: []),
        perryCoffee(PERRY_CHILL_GULP, steam: []),
        perryCoffee(PERRY_CHILL_DIP,  steam: []),
    ], fps: 2, loop: true)
)
