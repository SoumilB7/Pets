import AppKit

// DESIGN-OWNED. Pixel art for the "Cat" pet.
// Rules live in Design/PetSprite.swift. Preview with:  python3 tools/preview.py Cat --all
// Register new pets in Design/Registry.swift.
//
// Grey tabby: pointed ears with pink inners, an "M" of stripes on the forehead,
// stripes down the back, pink nose, green eye, and a tall tail that curls up
// behind the body (the tail flick is the idle pose). Airborne = full pounce stretch.

let CAT = PetSprite(
    name: "Cat",
    palette: ["o": OUT, "b": rgb(0.62, 0.62, 0.68), "t": rgb(0.42, 0.42, 0.50), "l": rgb(0.92, 0.92, 0.95),
              "e": rgb(0.25, 0.62, 0.35), "n": rgb(0.95, 0.55, 0.62), "k": rgb(1.00, 0.72, 0.78)],
    body: [
        "...........o...o..",
        "..........okoboko.",
        "..oo......obtbbtbo",
        ".obbo.....obbebbbo",
        ".otbo.....obbbbbno",
        ".obbo....obbbbbboo",
        ".otbootttttbbbbbo.",
        "..obbbbtbbbtbbbbo.",
        "...obbllllllllbbo.",
        "...obblllllllllbo.",
        "...obbbbbbbbbbbo..",
    ],
    bodyAlt: [  // tail flick + ear twitch
        "...........o......",
        "..........okoooko.",
        ".oo.......obtbbtbo",
        "obbo......obbebbbo",
        ".otbo.....obbbbbno",
        ".obbo....obbbbbboo",
        ".otbootttttbbbbbo.",
        "..obbbbtbbbtbbbbo.",
        "...obbllllllllbbo.",
        "...obblllllllllbo.",
        "...obbbbbbbbbbbo..",
    ],
    legsStand: ["....obbo..obbo....", "....obbo..obbo....", "....oooo..oooo...."],
    legsWalk:  ["...obbo....obbo...", "...obbo....obbo...", "...oooo....oooo..."],
    legsAir:   ["..obbo......obbo..", ".obbo........obbo.", "oooo..........oooo"],
    eyes: [(13, 3)], eyeColor: rgb(0.12, 0.38, 0.20), bodyChar: "b")

// ---- extras (engine hooks requested in DESIGN_REQUESTS.md) ----

private func catFront(eyes: String, mouth: String = "obbbobobbbo") -> [String] { [
    "....o........o....",
    "...oko......oko...",
    "...obtbbbbbbtbo...",
    "...o" + eyes + "o...",
    "...obbbbbbbbbbo...",
    "..oobbbbnnbbbboo..",
    "...." + mouth + "...",
    "...oobbbbbbbbboo..",
    "..obbbllllllbbbo..",
    "..obbbllllllbbbobo",
    "...obbbbbbbbbbo.bo",
    "....obbo..obbo..o.",
    "....obbo..obbo....",
    "....oooo..oooo....",
] }

/// Sitting upright on the bench, tail wrapped round the front, mug in both paws.
private let CAT_SIT_HOLD: [String] = [
    ".........o...o..",
    "........okoboko.",
    "........obtbbtbo",
    "........obbebbbo",
    "........obbbbbno",
    ".......obbbbbboo",
    "......obbtttbbo.",
    ".....obbtbbbbmcm",
    "....obbbbllbbmmm",
    "...obbbblllbbmm.",
    "..obbbbllllbbbo.",
    ".otttbbbbbbbbbo.",
    "..oooobbo..obbo.",
    "......obo..obo..",
    "......ooo..ooo..",
]
private let CAT_SIT_SIP: [String] = [
    ".........o...o..",
    "........okoboko.",
    "........obtbbtbo",
    "........obbebbbo",
    "........obbbbmmm",
    ".......obbbbbmmm",
    "......obbtttbbmm",
    ".....obbtbbbbbo.",
    "....obbbbllbbbo.",
    "...obbbblllbbbo.",
    "..obbbbllllbbbo.",
    ".otttbbbbbbbbbo.",
    "..oooobbo..obbo.",
    "......obo..obo..",
    "......ooo..ooo..",
]
private func catCoffee(_ pet: [String], steam: [(Int, Int)]) -> [String] {
    var f = onBench(pet, x: 5, y: 0)
    for (x, y) in steam { var l = Array(f[y]); if l[x] == "." { l[x] = "~" }; f[y] = String(l) }
    return f
}

let CAT_EXTRAS = PetExtras(
    palette: SCENE_PALETTE,
    front: AnimSeq(frames: [
        catFront(eyes: "bbebbbbebb"),
        catFront(eyes: "bbbbbbbbbb"),                         // blink
        catFront(eyes: "bebbbbbebb"),                         // glance
        catFront(eyes: "bbebbbbebb", mouth: "obbbokobbbo"),   // tiny tongue
    ], fps: 2, loop: true),
    fly: nil, exit: nil, enter: nil,
    coffee: AnimSeq(frames: [
        catCoffee(CAT_SIT_HOLD, steam: [(20, 6), (21, 5)]),
        catCoffee(CAT_SIT_HOLD, steam: [(21, 6), (20, 5)]),
        catCoffee(CAT_SIT_SIP,  steam: []),
        catCoffee(CAT_SIT_SIP,  steam: []),
    ], fps: 2, loop: true)
)
