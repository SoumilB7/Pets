import AppKit

// DESIGN-OWNED. Pixel art for the "Clawd" pet (the Claude Code mascot).
// Rules live in Design/PetSprite.swift. Preview with:  python3 tools/preview.py Clawd --all
// Register new pets in Design/Registry.swift.
//
// Warm orange rounded block with two dark eyes and stubby legs. Little side-arms:
// down in `body`, raised in `bodyAlt`, so idle = a slow wave and airborne = flailing.
// Clawd is symmetric, so the front view is the same block looking straight at you.

let CLAWD = PetSprite(
    name: "Clawd (Claude Code)",
    palette: ["o": rgb(0.55, 0.30, 0.20), "b": rgb(0.87, 0.48, 0.34), "B": rgb(0.93, 0.58, 0.42),
              "e": rgb(0.12, 0.08, 0.08)],
    body: [
        "..................",
        "....oooooooooo....",
        "...obBBBBBBBBbo...",
        "...obbbbbbbbbbo...",
        "...obbebbbbebbo...",
        "...obbebbbbebbo...",
        "...obbbbbbbbbbo...",
        "..obbbbbbbbbbbbo..",
        "..obbbbbbbbbbbbo..",
        "...obbbbbbbbbbo...",
        "....oooooooooo....",
    ],
    bodyAlt: [  // arms up
        "..................",
        "....oooooooooo....",
        ".b.obBBBBBBBBbo.b.",
        ".b.obbbbbbbbbbo.b.",
        ".obbbbebbbbebbbbo.",
        "...obbebbbbebbo...",
        "...obbbbbbbbbbo...",
        "...obbbbbbbbbbo...",
        "...obbbbbbbbbbo...",
        "...obbbbbbbbbbo...",
        "....oooooooooo....",
    ],
    legsStand: ["....obbo..obbo....", "....obbo..obbo....", "....oooo..oooo...."],
    legsWalk:  ["...obbo....obbo...", "...obbo....obbo...", "...oooo....oooo..."],
    legsAir:   ["...obbo....obbo...", "..obbo......obbo..", "..oooo......oooo.."],
    eyes: [(6, 5), (11, 5)], eyeColor: rgb(0.12, 0.08, 0.08), bodyChar: "b")

// ---- extras (engine hooks requested in DESIGN_REQUESTS.md) ----

private func clawdFront(eyes: String) -> [String] { [
    "..................",
    "....oooooooooo....",
    "...obBBBBBBBBbo...",
    "...obbbbbbbbbbo...",
    "...o" + eyes + "o...",
    "...o" + eyes + "o...",
    "...obbbbbbbbbbo...",
    "..obbbbbbbbbbbbo..",
    "..obbbbbbbbbbbbo..",
    "...obbbbbbbbbbo...",
    "....oooooooooo....",
    "....obbo..obbo....",
    "....obbo..obbo....",
    "....oooo..oooo....",
] }

private let CLAWD_SIT_HOLD: [String] = [
    "...oooooooooo...",
    "..obBBBBBBBBbo..",
    "..obbbbbbbbbbo..",
    "..obbebbbbebbo..",
    "..obbebbbbebbo..",
    "..obbbbbbbbbbo..",
    ".obbbbbbbbbbbmcm",
    ".obbbbbbbbbbbmmm",
    "..obbbbbbbbbbmm.",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "...oooooooooo...",
    "....obbo..obbo..",
    "....obbo..obbo..",
    "....oooo..oooo..",
]
private let CLAWD_SIT_SIP: [String] = [
    "...oooooooooo...",
    "..obBBBBBBBBbo..",
    "..obbbbbbbbbbo..",
    "..obbebbbbebbmmm",
    "..obbebbbbebbmmm",
    "..obbbbbbbbbbbmm",
    ".obbbbbbbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "..obbbbbbbbbbo..",
    "...oooooooooo...",
    "....obbo..obbo..",
    "....obbo..obbo..",
    "....oooo..oooo..",
]
private func clawdCoffee(_ pet: [String], steam: [(Int, Int)]) -> [String] {
    var f = onBench(pet, x: 5, y: 0)
    for (x, y) in steam { var l = Array(f[y]); if l[x] == "." { l[x] = "~" }; f[y] = String(l) }
    return f
}

let CLAWD_EXTRAS = PetExtras(
    palette: SCENE_PALETTE,
    front: AnimSeq(frames: [
        clawdFront(eyes: "bbebbbbebb"),
        clawdFront(eyes: "bbbbbbbbbb"),   // blink
        clawdFront(eyes: "bebbbbbebb"),   // glance left
        clawdFront(eyes: "bbbebbbbbe"),   // glance right
    ], fps: 2, loop: true),
    fly: nil, exit: nil, enter: nil,
    coffee: AnimSeq(frames: [
        clawdCoffee(CLAWD_SIT_HOLD, steam: [(19, 5), (20, 4)]),
        clawdCoffee(CLAWD_SIT_HOLD, steam: [(20, 5), (19, 4)]),
        clawdCoffee(CLAWD_SIT_SIP,  steam: []),
        clawdCoffee(CLAWD_SIT_SIP,  steam: []),
    ], fps: 2, loop: true)
)
