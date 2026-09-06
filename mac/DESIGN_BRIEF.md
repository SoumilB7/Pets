# PixelPet — Design brief

You are the DESIGN agent for PixelPet, a tiny always-on-top pixel-art desktop pet for macOS
(native Swift/AppKit, no Xcode, built with `swiftc`). Another agent owns the ENGINE
(behaviour, physics, window-hopping, menus). You two work in parallel in the same repo,
so the split below is strict.

## Where things are

```
mac/
  Design/                ← YOURS
    PetSprite.swift      ← the CONTRACT. Read it first. Do not edit without asking.
    Effects.swift        ← hearts, dizzy stars, happy/dizzy eye overlays (yours)
    Registry.swift       ← ordered list of pets shown in the menu (yours)
    Pets/
      Dog.swift  Cat.swift  Perry.swift  Dragon.swift  Clawd.swift   (yours)
  Engine/                ← NOT YOURS. Don't edit. Read if curious.
    Core/ Sense/ World/ Brain/ Body/ App/ UI/   (see ARCHITECTURE.md)
  tools/preview.py       ← render a pet in the terminal, validate widths
  run.sh                 ← build + relaunch the app
```

## What a pet is

One `PetSprite` value (see `Design/PetSprite.swift`). Pixel art is plain strings, one
character per pixel, `.` = transparent, every other character looked up in the pet's
`palette`. The grid is:

- `body` (11 rows for current pets) + `legsStand` (3 rows) = the standing frame.
- `bodyAlt` = idle animation pose. Engine flips body/bodyAlt slowly when idle, fast when
  airborne, never while walking. Tail wag, wing flap, glance, breathing all go here.
- `legsWalk` = alternated with `legsStand` while walking.
- `legsAir` = used while thrown / held / falling.
- `e` characters are EYES. Blinking replaces every `e` with `bodyChar`. Use `e` only for eyes.
- `eyes: [(col,row)]` tells the engine where to draw the `^` (petted) and `X` (dizzy) overlays.
- Sprites FACE RIGHT. The engine mirrors them to face left.
- All rows across all five arrays must be the same width. 18 is the house width; you may
  go wider, but keep every row in that pet equal. The bottom leg row is the feet and sits
  on the floor / window ledge.

Pixel size on screen is 4 pt, so an 18×14 pet is 72×56 pt. Keep pets small and readable.

## Workflow

1. Edit or add files in `Design/Pets/`. Add new pets to `Design/Registry.swift`.
2. Preview without building: `python3 tools/preview.py Dog --all`
3. Validate all: `python3 tools/preview.py --check`
4. Build + relaunch to see it live: `./run.sh` (from `mac/`). Sprite validation errors
   print to stderr at launch; the app still runs.

## What the engine does with your art (so you can design for it)

- Walks along the bottom of the screen and along the top edges of open windows.
- Jumps between windows with a ballistic arc (uses `legsAir`, flips `bodyAlt` fast).
- Can be grabbed, dragged, thrown; bounces off floor, walls, ceiling.
- Hard impact → dizzy for ~2 s: `X` eyes + orbiting stars (`Effects.drawStars`), wobble.
- Hover-rubbing → petted: `^` eyes + floating hearts (`Effects.drawHeart`).
- Idle: gentle 1 px bob plus your body/bodyAlt swap.

## Asks

- Polish the five existing pets (Dog, Cat, Perry the Platypus, Baby Dragon, Clawd the
  Claude Code mascot). Make each unmistakable at 4 pt/pixel. Stronger silhouettes,
  better idle poses, cleaner outlines.
- Give each pet a distinctive `bodyAlt` and `legsAir`.
- Improve `Effects.swift` if you like (hearts, stars) but keep the function signatures.
- Feel free to add pets. Register them; the menu picks them up automatically.

## Do not

- Edit anything in `Engine/`, `run.sh`, or `Design/PetSprite.swift`. If you need a new
  hook (e.g. a "sleeping" frame, a bark bubble), write the request in
  `mac/DESIGN_REQUESTS.md` with the field/function you'd want and the engine agent will add it.
- Change the `Effects` function signatures or the `PetSprite` field names.
- Mix row widths inside one pet. `tools/preview.py --check` must print `all pets OK`.
