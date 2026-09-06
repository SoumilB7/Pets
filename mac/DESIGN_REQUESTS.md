# Design → Engine requests

Everything below is already drawn and compiles. It lives in `Design/Registry.swift`
(`AnimSeq`, `PetExtras`, `PET_EXTRAS`, `validateExtras`, `BENCH_SCENE`) and in each
`Design/Pets/<Name>.swift` as `<NAME>_EXTRAS`. Nothing in `PetSprite` changed.
Look up extras with `PET_EXTRAS[pet.name]`; every field is optional, so a pet
without a sequence simply falls back to today's behaviour.

```swift
struct AnimSeq { let frames: [[String]]; let fps: Double; let loop: Bool; var cols: Int; var rows: Int }
struct PetExtras { let palette: [Character: NSColor]; let front, fly, exit, enter, coffee: AnimSeq? }
```

Frames are full sprites (body + legs rows, feet on the last row) and may be wider
or taller than `pet.cols`/`pet.rows`, so the window needs to size to `seq.cols × PX`
by `seq.rows × PX` while a sequence plays. Colours: `pet.palette.merging(extras.palette)`.
Please call `validateExtras(pet.name, extras, base: pet)` at launch next to
`pet.validate()` and print problems to stderr the same way.

## 1. Front-facing state ("it can see me")  — `front`
- 3–4 frames at 2 fps, looping: neutral, blink, glance, (Dragon: ember puff; Cat: tongue).
- Ask: when idle, occasionally (say 20 % of idle bouts, 2–4 s) turn to face the user and
  play `front`. Also face the user when the cursor comes within ~120 pt and stops, and for
  a moment after being petted. Never mirror these frames.
- `pet.eyes` are side-view coordinates, so skip the ^ / X overlays while `front` is showing,
  or use frame 1 (blink) instead.

## 2. Dragon flight  — `fly`, plus a menu option
- Dragon has a 3-frame `fly` loop (22 wide) at 6 fps: wing up / level / down.
- Ask: for pets with `fly != nil`, every idle bout roll against **Flight chance** and, on
  success, take off: climb in a gentle sine path, cruise across the screen for 4–8 s
  (bank = mirror on direction change), then land on the nearest window top or the floor
  and resume walking. Use `fly` frames the whole time instead of `legsAir`/`bodyAlt`.
- Menu: a "Flight chance" submenu with Never / 10 % / 25 % / 50 % / Always, persisted in
  `UserDefaults` (e.g. key `flightChance`). Hidden or disabled for pets without `fly`.
- When a flying pet must leave the screen (see 3), let it fly off the edge rather than
  walk.

## 3. Pet-specific exit / enter  — `exit`, `enter`
- Perry has an 8-frame `exit` at 8 fps: a dark hatch opens under his feet, he drops into
  his secret tube, hat last, the hatch closes. `enter` is the reverse. Both are 18×14,
  same footprint as the standing sprite, so no window resize.
- Ask: play `exit` whenever the pet leaves the screen: switching pets in the menu,
  "Hide pet", quitting, or moving to another display; play `enter` when it comes back.
  Pets without `exit` walk/fly off the edge as they do now. Please add a "Hide / Show pet"
  menu item so the exit can be triggered on demand (⌃⌥H would be nice).

## 4. Modes  — `coffee` (shared by all five pets)
- Every pet has a 4-frame `coffee` loop at 2 fps: sitting on a beach bench on sand,
  steam wisps rising, then a sip. Frames are 26×18. Sand is the bottom two rows, so the
  frame's feet-on-floor rule still holds.
- Ask: a "Mode" submenu with **Normal** and **Coffee break** (more to come: the scene
  helper `onBench` in Registry.swift makes new shared modes cheap). In Coffee break the
  pet stops wandering, plays `coffee` in place on its current ledge, and still responds
  to petting (hearts) but not to throwing. Persist the mode. Return to Normal via the menu
  or automatically after N minutes if you prefer.

## 5. Small things
- `Effects.drawHeart` now draws a 7×6 heart (was 5×4); spawn x range may want +5 pt.
- `Effects.drawStars` uses alpha to fake depth; nothing to change on your side.
- A future request: a `sleep` sequence for a "Nap" mode. Not drawn yet.
