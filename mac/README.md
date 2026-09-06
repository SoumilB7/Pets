# PixelPet (macOS)

Tiny pixel-art desktop pet. Always on top, click-through-free, no dock icon, controlled
from a 🐶 menu bar item. Built with plain `swiftc`, no Xcode project.

```
./run.sh              # build the .app bundle into build/ and (re)launch it
./install.sh          # build + copy to /Applications and launch
pkill -x PixelPet     # stop
```

The app window (Open PixelPet from the 🐾 menu) has three pages:
**Pet** (all per-pet settings), **Tasks** (a board of sticky notes) and **State Space**
(every window you use, embedded on-device and linked to the closest task; auto-updates on
focus changes and every 5 minutes; optional mirror to Actian VectorAI DB).

## Layout

See `ARCHITECTURE.md` for the full map. Short version: `Design/` is pixel art (design
agents), `Engine/` is behaviour split by role (`Sense`, `World`, `Brain`, `Body`, `App`,
`UI`, `Core`), `tools/` has the sprite previewer, icon builder and smoke test.

```
tools/smoke.sh        # build, run 35 s, assert on the log and state stream
```

See `DESIGN_BRIEF.md` for the design agent's instructions.
