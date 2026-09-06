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
│   ├── Sense/                   what the pet knows about the outside world
│   │   ├── Spaces.swift         desktops / fullscreen apps (SkyLight, read-only)
│   │   ├── Context.swift        frontmost app, window title, URL, category
│   │   └── State.swift          you-vs-pet state stream → state.jsonl
│   ├── World/
│   │   └── Platforms.swift      windows → ledges, occlusion, main window
│   ├── Brain/
│   │   ├── Decide.swift         where to go next; hops, climbs, take-off walks
│   │   └── Desktops.swift       leaving / arriving on desktops
│   ├── Body/
│   │   ├── Physics.swift        the 60 Hz tick + chill mode
│   │   └── Interaction.swift    grab / drag / release / impacts
│   ├── Mind/                    the State Space (capture → embed → store → link)
│   │   ├── Tasks.swift          sticky-note model, tasks.json, 30-day archive
│   │   ├── Capture.swift        window → text (AX text sample), deterministic node ids
│   │   ├── Embed.swift          Embedder protocol; Hybrid(apple sentence 512-d + keyword hash 512-d)
│   │   ├── Store.swift          VectorStore protocol; LocalStore (JSON); ActianStore (REST)
│   │   ├── Link.swift           edges: cosine ≥ threshold × recency half-life; SpaceGraph
│   │   └── Mind.swift           coordinator, settings, triggers (focus 2 s debounce, sweep every 5 min, manual)
│   ├── App/
│   │   └── AppDelegate.swift    all stored state, launch, menus, modes, pet selection
│   └── UI/
│       ├── Render.swift         PetView: draws a PetSprite frame
│       ├── Preferences.swift    the app window: sidebar (Pet · Tasks · State Space) + the Pet page
│       ├── TasksPage.swift      kanban of sticky notes
│       └── StateSpacePage.swift status · now strip · graph (GraphView) · linked windows · store settings
├── tools/
│   ├── preview.py               terminal preview + width check for sprites
│   ├── make-icon.py             renders the dog into AppIcon.icns
│   ├── smoke.sh                 build → launch → assert on log + state stream + state space
│   └── test-mind.sh             headless: embed → store → link assertions (tools/test-mind/main.swift)
├── build-app.sh                 assemble build/PixelPet.app
├── run.sh                       build + relaunch (dev loop)
└── install.sh                   build + copy to /Applications + launch
```

## Data flow, once per frame (60 Hz)

```
tick()
 ├─ every 1 s: Context.refresh() → sampleState() → StateLog (log [state], append jsonl)
 ├─ mode gate: Action → hide; Chill → tickChill(); Normal ↓
 ├─ desktops: Spaces.active() → show/hide window; frozen + maybe return if elsewhere
 ├─ every 0.1 s: refreshPlatforms() → platforms, frontWindow (log [scan]/[front])
 ├─ mouse: only the sprite is clickable; rubbing = petting
 ├─ movement branch: held | climbing | airborne | skidding | dizzy/petted | walking
 │     walking → nextWander due → pickWanderTarget() (log [decide]) → travel()
 └─ frame: legs + body/bodyAlt + eyes → PetView
```

## State Space data flow

```
[front]/[scan] change ──debounce 2 s──►  Mind.captureFocused()  ─► Capture.focused (AX text ≤ 2000 chars, ≤150 ms)
every 5 min / manual ────────────────►  Mind.sweep()           ─► Capture.windows (titles of every visible app)
                                              │
                                              ▼  ingest(): same nodeId + same hash → touch lastSeen only
                                        Embed (hybrid 1024-d) ─► LocalStore.upsert (+ ActianStore mirror if reachable)
                                              │
Tasks board change ─► embedTasks() ───────────┤
                                              ▼
                                        Link.build ─► edges.json ─► .spaceRefreshed ─► StateSpacePage.render()
```

Retention keeps `windows` ≤ 3,000 (≤ 40 per app) so the Actian Community cap (5,000) is never hit.

## Files the app writes

| Path | What |
|---|---|
| `~/Library/Logs/PixelPet.log` | this run's events (see tag list in `Log.swift`) |
| `~/Library/Logs/PixelPet.prev.log` | previous run |
| `~/Library/Application Support/PixelPet/state.jsonl` | one JSON line per state change / 30 s heartbeat; rolls at 10 MB |
| `…/tasks.json` · `tasks-archive.jsonl` | the board; done tasks older than 30 days |
| `…/snapshots.jsonl` | every captured window snapshot; rolls at 20 MB |
| `…/vectors.local.json` | LocalStore (windows + tasks collections) |
| `…/edges.json` | the current SpaceGraph |
| `defaults com.soumil.pixelpet` | settings (per pet, JSON blobs), mode, pet index, `mind.*` keys |

## Conventions

- Stored properties only in `AppDelegate`; behaviour in extensions by role.
- Every collision goes through `bonk()`; every destination through `travel()`; every
  desktop move through `arrive()`. Log there, not at call sites.
- Nothing logs per frame. `[pos]` is the only periodic line (10 s, normal mode).
- Settings are read live via `S`; never cache a setting across frames.
- Design/Engine only meet at `PetSprite`, `PetExtras`, and the `Effects` signatures.
