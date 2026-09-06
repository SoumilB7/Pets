# PixelPet (macOS)

Tiny pixel-art desktop pet. Always on top, click-through-free, no dock icon, controlled
from a 🐶 menu bar item. Built with plain `swiftc`, no Xcode project.

```
./run.sh              # build the .app bundle into build/ and (re)launch it
./install.sh          # build + copy to /Applications and launch
./install-saver.sh    # build PixelPet.saver and install it for this user
pkill -x PixelPet     # stop
```

## Screen saver

`Saver/` builds `PixelPet.saver`: your wallpaper with the selected pet wandering along the
bottom. It reads the same pet choice and per-pet settings as the app and works with the
app switched off ("Pet active" in the menu bar). `tools/test-saver.sh` renders one frame
headlessly to `build/saver-frame.png`.

The app window (Open PixelPet from the 🐾 menu) holds every per-pet setting:
General, Zone, Movement, Physics, Animations, App.

## Layout

See `ARCHITECTURE.md` for the full map. Short version: `Design/` is pixel art (design
agents), `Engine/` is behaviour split by role (`Sense`, `World`, `Brain`, `Body`, `App`,
`UI`, `Core`), `tools/` has the sprite previewer, icon builder and smoke test.

```
tools/smoke.sh        # build, run 35 s, assert on the log
```

See `DESIGN_BRIEF.md` for the design agent's instructions.
