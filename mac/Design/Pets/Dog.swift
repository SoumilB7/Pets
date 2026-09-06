import AppKit

// DESIGN-OWNED. Pixel art for the "Dog" pet.
// Rules live in Design/PetSprite.swift. Preview with:  python3 tools/preview.py Dog --all
// Register new pets in Design/Registry.swift.
//
// Golden pup: one big floppy ear hanging down the back of the head, light muzzle with a
// dark nose, red collar, stubby wagging tail. Idle = tail wag + ear lift; air = legs splayed.

let DOG = PetSprite(
    name: "Dog",
    palette: ["o": OUT, "b": rgb(0.93, 0.64, 0.30), "d": rgb(0.72, 0.45, 0.20), "l": rgb(1.00, 0.92, 0.76),
              "e": rgb(0.15, 0.10, 0.15), "n": rgb(0.22, 0.14, 0.18), "r": rgb(0.86, 0.20, 0.22),
              "k": rgb(1.00, 0.48, 0.58)],
    body: [
        "..........oooooo..",
        "........oobbbbbbo.",
        ".oo....oddobbebbbo",
        "obbo...oddobbbbllo",
        "obbbo..oddobbblnno",
        ".obbboooodobbbbboo",
        "..obbbbbbbbbrrrrro",
        "...obbbbbbbbbbbbo.",
        "...obbllllllllbbo.",
        "...obblllllllllbo.",
        "...obbbbbbbbbbbo..",
    ],
    bodyAlt: [  // tail wag + ear flap + tongue out
        "..........oooooo..",
        ".oo.....oobbbbbbo.",
        "obbo...oddobbebbbo",
        "obbbo..oddobbbbllo",
        ".obbo..oddobbblnno",
        "..obbooooodbbbbboo",
        "..obbbbbbbbbrrrrko",
        "...obbbbbbbbbbbbo.",
        "...obbllllllllbbo.",
        "...obblllllllllbo.",
        "...obbbbbbbbbbbo..",
    ],
    legsStand: ["....obbo..obbo....", "....obbo..obbo....", "....oooo..oooo...."],
    legsWalk:  ["...obbo....obbo...", "...obbo....obbo...", "...oooo....oooo..."],
    legsAir:   ["..obbo......obbo..", "..obbo......obbo..", "..oooo......oooo.."],
    eyes: [(13, 2)], eyeColor: rgb(0.15, 0.10, 0.15), bodyChar: "b")

// ---- extras (engine hooks requested in DESIGN_REQUESTS.md) ----

private func dogFront(eyes: String, mouth: String = "obbllkllbbo") -> [String] { [
    "......oooooo......",
    "....oobbbbbbbboo..",
    "...oddobbbbbbboddo",
    "...oddo" + eyes + "oddo",
    "...oddobbbbbbboddo",
    "...oddobblnlbboddo",
    "......" + mouth + ".",
    "....obbrrrrrrrbo..",
    "...obbbllllllbbbo.",
    "...obbbllllllbbbo.",
    "....obbbbbbbbbbo..",
    "....obbo..obbo....",
    "....obbo..obbo....",
    "....oooo..oooo....",
] }

private let DOG_SIT_HOLD: [String] = [
    "........oooooo..",
    "......oobbbbbbo.",
    ".....oddobbebbbo",
    ".....oddobbbbllo",
    ".....oddobbblnno",
    "....ooooodbbbboo",
    "...obbbbbbbrrrro",
    "..obbbbbbbbbbmcm",
    ".obbbbbllllbbmmm",
    "oobbbbllllllbmm.",
    "obbbbbllllllbbo.",
    ".oobbbbbbbbbbbo.",
    "...oooobbo.obbo.",
    "......obbo.obbo.",
    "......oooo.oooo.",
]
private let DOG_SIT_SIP: [String] = [
    "........oooooo..",
    "......oobbbbbbo.",
    ".....oddobbebbbo",
    ".....oddobbbbmmm",
    ".....oddobbbbmmm",
    "....ooooodbbbbmm",
    "...obbbbbbbrrrro",
    "..obbbbbbbbbbbo.",
    ".obbbbbllllbbbo.",
    "oobbbbllllllbbo.",
    "obbbbbllllllbbo.",
    ".oobbbbbbbbbbbo.",
    "...oooobbo.obbo.",
    "......obbo.obbo.",
    "......oooo.oooo.",
]
private func dogCoffee(_ pet: [String], steam: [(Int, Int)]) -> [String] {
    var f = onBench(pet, x: 5, y: 0)
    for (x, y) in steam { var l = Array(f[y]); if l[x] == "." { l[x] = "~" }; f[y] = String(l) }
    return f
}

let DOG_EXTRAS = PetExtras(
    palette: SCENE_PALETTE,
    front: AnimSeq(frames: [
        dogFront(eyes: "bebbbeb"),
        dogFront(eyes: "bbbbbbb"),                          // blink
        dogFront(eyes: "ebbbebb"),                          // glance
        dogFront(eyes: "bebbbeb", mouth: "obbllkllbbo"),  // (tongue is always out, it's a dog)
    ], fps: 2, loop: true),
    fly: nil, exit: nil, enter: nil,
    coffee: AnimSeq(frames: [
        dogCoffee(DOG_SIT_HOLD, steam: [(19, 6), (20, 5)]),
        dogCoffee(DOG_SIT_HOLD, steam: [(20, 6), (19, 5)]),
        dogCoffee(DOG_SIT_SIP,  steam: []),
        dogCoffee(DOG_SIT_SIP,  steam: []),
    ], fps: 2, loop: true)
)
