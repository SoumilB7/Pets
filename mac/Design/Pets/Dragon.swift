import AppKit

// DESIGN-OWNED. Pixel art for the "Baby Dragon" pet.
// Rules live in Design/PetSprite.swift. Preview with:  python3 tools/preview.py Dragon --all
// Register new pets in Design/Registry.swift.
//
// Round green body, cream belly, two cream horns, a dark-green bat wing on the back,
// an arrow-tipped tail behind, a blunt snout with a nostril. bodyAlt raises the wing
// so the airborne fast-flip reads as flapping. `fly` frames are a real gliding pose.

let DRAGON = PetSprite(
    name: "Baby Dragon",
    palette: ["o": OUT, "b": rgb(0.36, 0.72, 0.36), "l": rgb(0.84, 0.95, 0.66), "g": rgb(0.20, 0.50, 0.26),
              "h": rgb(1.00, 0.93, 0.70), "e": rgb(0.13, 0.09, 0.13), "N": rgb(0.22, 0.48, 0.24),
              "f": rgb(1.00, 0.55, 0.15), "F": rgb(1.00, 0.85, 0.30)],
    body: [
        "...........h...h..",
        "..........ohbbbhoo",
        "..........obbbebbo",
        ".....gg...obbbbbbo",
        ".oo..ggg..obbbbbNo",
        "obbo.gggg.obbbbooo",
        ".obbooggggbbbbbbo.",
        "..obbbbggbbbbbllo.",
        "...obbbbbbbbbllllo",
        "...obbllllllllllo.",
        "...obbbbbbbbbbbo..",
    ],
    bodyAlt: [  // wing up + tail lifted
        "...........h...h..",
        "...gg.....ohbbbhoo",
        "...ggg....obbbebbo",
        "....gggg..obbbbbbo",
        ".oo.ggggg.obbbbbNo",
        "obbo.gggg.obbbbooo",
        ".obboo.gggbbbbbbo.",
        "..obbbbbgbbbbbllo.",
        "...obbbbbbbbbllllo",
        "...obbllllllllllo.",
        "...obbbbbbbbbbbo..",
    ],
    legsStand: ["....obbo..obbo....", "....obbo..obbo....", "...ooooo.ooooo...."],
    legsWalk:  ["...obbo....obbo...", "...obbo....obbo...", "..ooooo...ooooo..."],
    legsAir:   ["...obbo....obbo...", "..obbo......obbo..", ".ooooo......ooooo."],
    eyes: [(14, 2)], eyeColor: rgb(0.13, 0.09, 0.13), bodyChar: "b")

// ---- extras (engine hooks requested in DESIGN_REQUESTS.md) ----

private func dragonFront(eyes: String, mouth: String = "obbbobbobbbo") -> [String] { [
    "....h.......h.....",
    "....h.......h.....",
    "...ohbbbbbbbbho...",
    "...o" + eyes + "o...",
    "...obbbbbbbbbbo...",
    "gg." + mouth + ".gg",
    "gggobbbbbbbbbbbogg",
    "gggobbbllllllbbogg",
    ".ggobbllllllllbogg",
    "..oobbllllllllboo.",
    "...obbbbbbbbbbo...",
    "....obbo..obbo....",
    "....obbo..obbo....",
    "...ooooo.ooooo....",
] }

/// Gliding, 22 wide × 14 tall. Legs tucked, tail streaming behind, wing beats down/up.
private let DRAGON_FLY: [[String]] = [
    [   // wing up
        ".......gg.............",
        ".......ggg............",
        "........gggg...h...h..",
        "........ggggg.ohbbbhoo",
        ".........gggg.obbbebbo",
        "oo........gggobbbbbbbo",
        "obbo......ggobbbbbbbNo",
        ".obboooooobbbbbbbbbooo",
        "..obbbbbbbbbbbbbbbbbo.",
        "...obblllllllllllllo..",
        "....obbllllllllllbo...",
        ".....obbbbobbbbbbo....",
        "......oooo.oooo.......",
        "......................",
    ],
    [   // wing level
        "......................",
        "......................",
        "...............h...h..",
        "..............ohbbbhoo",
        "..............obbbebbo",
        "oo...........obbbbbbbo",
        "obbo.gggggggggbbbbbbNo",
        ".obboooooggggbbbbbbooo",
        "..obbbbbbbbbbbbbbbbbo.",
        "...obblllllllllllllo..",
        "....obbllllllllllbo...",
        ".....obbbbobbbbbbo....",
        "......oooo.oooo.......",
        "......................",
    ],
    [   // wing down
        "......................",
        "......................",
        "...............h...h..",
        "..............ohbbbhoo",
        "..............obbbebbo",
        "oo...........obbbbbbbo",
        "obbo.........obbbbbbNo",
        ".obbooooooobbbbbbbbooo",
        "..obbbbbgggbbbbbbbbbo.",
        "...obbllggggllllllo...",
        "....obblgggggllllbo...",
        ".....obbbbggggbbbo....",
        "......oooo.gggo.......",
        "...........gg.........",
    ],
]

/// Sitting on the bench, wing folded, tail hanging down behind the bench, mug in claws.
private let DRAGON_SIT_HOLD: [String] = [
    ".........h...h..",
    "........ohbbbhoo",
    "........obbbebbo",
    "...gg...obbbbbbo",
    "...ggg..obbbbbNo",
    "...gggg.obbbbooo",
    "..obggggbbbbbbo.",
    ".obbbbggbbbbbbo.",
    ".obbbbbbbbbbbmcm",
    ".obbbllllllllmmm",
    "oobbbllllllllmm.",
    "obbbbbbbbbbbbbo.",
    "obbbobbo.obbo...",
    ".oo.obbo.obbo...",
    "...ooooo.ooooo..",
]
private let DRAGON_SIT_SIP: [String] = [
    ".........h...h..",
    "........ohbbbhoo",
    "........obbbebbo",
    "...gg...obbbbbbo",
    "...ggg..obbbbmmm",
    "...gggg.obbbbmmm",
    "..obggggbbbbbbmm",
    ".obbbbggbbbbbbo.",
    ".obbbbbbbbbbbbo.",
    ".obbbllllllllbo.",
    "oobbbllllllllbo.",
    "obbbbbbbbbbbbbo.",
    "obbbobbo.obbo...",
    ".oo.obbo.obbo...",
    "...ooooo.ooooo..",
]
private func dragonCoffee(_ pet: [String], steam: [(Int, Int)]) -> [String] {
    var f = onBench(pet, x: 5, y: 0)
    for (x, y) in steam { var l = Array(f[y]); if l[x] == "." { l[x] = "~" }; f[y] = String(l) }
    return f
}

let DRAGON_EXTRAS = PetExtras(
    palette: SCENE_PALETTE,
    front: AnimSeq(frames: [
        dragonFront(eyes: "bbebbbbebb"),
        dragonFront(eyes: "bbbbbbbbbb"),                              // blink
        dragonFront(eyes: "bebbbbbebb"),                              // glance
        dragonFront(eyes: "bbebbbbebb", mouth: "obbbFffFbbbo"),       // little smoke-puff / ember
    ], fps: 2, loop: true),
    fly: AnimSeq(frames: DRAGON_FLY, fps: 6, loop: true),
    exit: nil,    // dragon leaves by flying off-screen with `fly`
    enter: nil,
    coffee: AnimSeq(frames: [
        dragonCoffee(DRAGON_SIT_HOLD, steam: [(19, 7), (20, 6)]),
        dragonCoffee(DRAGON_SIT_HOLD, steam: [(20, 7), (19, 6)]),
        dragonCoffee(DRAGON_SIT_SIP,  steam: []),
        dragonCoffee(DRAGON_SIT_SIP,  steam: []),
    ], fps: 2, loop: true)
)
