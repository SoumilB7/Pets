# PixelPet architecture

Native Swift/AppKit, no Xcode project, built by `build-app.sh` with `swiftc` over every
`.swift` under `Engine/` and `Design/`. Two compartments, one contract.

```
mac/
├── Design/                      DESIGN agents own this
│   ├── PetSprite.swift          the contract type + validate()   (frozen)
│   ├── Effects.swift            hearts, stars, eye overlays      (signatures frozen)
│   ├── Registry.swift           PETS list, PetExtras (front/fly/exit/enter/coffee)
│   └── Pets/*.swift             one pet per file
├── Engine/                      ENGINE agents own this
│   ├── Core/
│   │   ├── main.swift           entry point; validates sprites at launch
│   │   ├── Log.swift            event log + tag reference
│   │   └── Settings.swift       PetSettings (per pet, `S`), Mode, HomeZone, DizzyMode
│   ├── Sense/
│   │   └── Spaces.swift         desktops / fullscreen apps (SkyLight, read-only)
│   ├── World/
│   │   └── Platforms.swift      windows → ledges, occlusion, main window
│   ├── Brain/
│   │   ├── Decide.swift         where to go next; hops, climbs, take-off walks
│   │   └── Desktops.swift       leaving / arriving on desktops
│   ├── Body/
│   │   ├── Physics.swift        the 60 Hz tick + chill mode
│   │   └── Interaction.swift    grab / drag / release / impacts
│   ├── App/
│   │   └── AppDelegate.swift    all stored state, launch, menus, modes, pet selection
│   └── UI/
│       ├── Render.swift         PetView: draws a PetSprite frame
│       └── Preferences.swift    the app window (tabs of per-pet settings)
├── Saver/                   the screen saver (same Design/ + settings model, own view)
│   ├── PetSaverView.swift   wallpaper + pet on the floor: wander, hop, blink, nap
│   ├── Globals.swift        the `pet` global the settings code expects
│   └── Info.plist
├── tools/
│   ├── preview.py               terminal preview + width check for sprites
│   ├── make-icon.py             renders the dog into AppIcon.icns
│   ├── smoke.sh                 build → launch → assert on the log
│   └── test-saver.sh            load PixelPet.saver headlessly, render a frame
├── build-app.sh                 assemble build/PixelPet.app
├── run.sh                       build + relaunch (dev loop)
└── install.sh                   build + copy to /Applications + launch
```

## Data flow, once per frame (60 Hz)

```
tick()
 ├─ mode gate: Action → hide; Chill → tickChill(); Normal ↓
 ├─ desktops: Spaces.active() → show/hide window; frozen + maybe return if elsewhere
 ├─ every 0.1 s: refreshPlatforms() → platforms, frontWindow (log [scan]/[front])
 ├─ mouse: only the sprite is clickable; rubbing = petting
 ├─ movement branch: held | climbing | airborne | skidding | dizzy/petted | walking
 │     walking → nextWander due → pickWanderTarget() (log [decide]) → travel()
 └─ frame: legs + body/bodyAlt + eyes → PetView
```

## Files the app writes

| Path | What |
|---|---|
| `~/Library/Logs/PixelPet.log` | this run's events (see tag list in `Log.swift`) |
| `~/Library/Logs/PixelPet.prev.log` | previous run |
| `defaults com.soumil.pixelpet` | settings (per pet, JSON blobs), mode, pet index, `mind.*` keys |

## Conventions

- Stored properties only in `AppDelegate`; behaviour in extensions by role.
- Every collision goes through `bonk()`; every destination through `travel()`; every
  desktop move through `arrive()`. Log there, not at call sites.
- Nothing logs per frame. `[pos]` is the only periodic line (10 s, normal mode).
- Settings are read live via `S`; never cache a setting across frames.
- Design/Engine only meet at `PetSprite`, `PetExtras`, and the `Effects` signatures.
