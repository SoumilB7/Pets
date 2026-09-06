import AppKit

// The engine's settings code refers to a global `pet` (the selected sprite). The screen saver
// keeps its own copy so Engine/Core/Settings.swift compiles unchanged in this bundle.
var pet: PetSprite = PETS[0]
