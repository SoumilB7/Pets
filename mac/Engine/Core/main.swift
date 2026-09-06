import AppKit

// ENGINE entry point. Top-level code is only allowed in main.swift.
// Sprite problems are printed to stderr at launch but never stop the app.
for p in PETS {
    for problem in p.validate() { FileHandle.standardError.write((problem + "\n").data(using: .utf8)!) }
    if let x = PET_EXTRAS[p.name] { for problem in validateExtras(p.name, x, base: p) { FileHandle.standardError.write((problem + "\n").data(using: .utf8)!) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
