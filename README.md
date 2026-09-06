# PixelPet

A tiny pixel-art companion that lives on your Mac, walks along your windows, and knows when you're on task.

**[⬇ Download for macOS](https://github.com/SoumilB7/Pets/releases/latest)** · macOS 13+ · first launch: right-click → Open

<p align="center">
  <a href="https://youtu.be/VGo96MaF6w4"><img src="docs/media/tutorial-poster.jpg" alt="Watch the tutorial" width="720"></a><br>
  <a href="https://youtu.be/VGo96MaF6w4">▶ 5-minute tutorial</a>
</p>

## What it does

- Five pixel pets: Dog, Cat, Perry the Platypus, Baby Dragon, Clawd. Grab, throw, pet them.
- Walks on top of your windows, climbs their sides, follows you across desktops and fullscreen apps.
- Three modes: Normal, Chill, Action. Every behaviour is a per-pet setting.
- `main` adds a sticky-note task board and a **State Space**: each window you use is embedded on-device and linked to the closest task. The pet gets out of the way while you're on task and restless when you drift.

## Install

Download the DMG from the [latest release](https://github.com/SoumilB7/Pets/releases/latest) and drag PixelPet into Applications. Two images: `PixelPet-x.y.dmg` (everything) and `PixelPet-x.y-pets-only.dmg` (just the pets).

The app is signed locally, not through Apple, so the first time: right-click PixelPet → **Open** → **Open**. Window titles need Accessibility access; the app asks once. Nothing leaves your Mac.

Build from source (needs Xcode Command Line Tools):

```sh
cd mac && ./install.sh      # build → /Applications → launch
./make-dmg.sh               # build a disk image
tools/smoke.sh              # build, run, assert on the log
```

## Branches

`main` — full app. `pets-only` — pets and settings, nothing else.

## Layout

```
mac/Design/    pixel art, one file per pet
mac/Engine/    behaviour, physics, rendering, settings, UI
mac/tools/     preview, icon, signing, smoke test
docs/media/    tutorial poster
```

Details in [mac/ARCHITECTURE.md](mac/ARCHITECTURE.md). Drawing a new pet: [mac/DESIGN_BRIEF.md](mac/DESIGN_BRIEF.md).

MIT © Soumil
