import AppKit
import ScreenSaver

// Loads build/PixelPet.saver the way the system does, animates it, and writes one frame to a PNG.
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/PixelPet.saver"
guard let bundle = Bundle(path: path) else { print("no bundle at \(path)"); exit(1) }
guard bundle.load(), let cls = bundle.principalClass as? ScreenSaverView.Type else { print("bundle failed to load or has no ScreenSaverView principal class"); exit(1) }
print("principal class:", NSStringFromClass(cls))
let size = NSRect(x: 0, y: 0, width: 1440, height: 900)
guard let view = cls.init(frame: size, isPreview: false) else { print("init failed"); exit(1) }
let win = NSWindow(contentRect: size, styleMask: .borderless, backing: .buffered, defer: false)
win.contentView = view
view.startAnimation()
for _ in 0..<150 { view.animateOneFrame() }
guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { print("no bitmap"); exit(1) }
view.cacheDisplay(in: view.bounds, to: rep)
let out = "build/saver-frame.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("frame written to \(out)")
