import AppKit
import ScreenSaver

// PixelPet screen saver. Draws your desktop wallpaper, then the currently selected pet
// (same sprites and per-pet settings as the app) wandering along the bottom of the screen.
// No windows exist inside a screen saver, so there are no ledges here: floor only.

@objc(PetSaverView)
final class PetSaverView: ScreenSaverView {
    // world
    private var wallpaper: NSImage?
    private var petSprite: PetSprite = PETS[0]
    private var cfg = PetSettings()
    private var px: CGFloat = 4

    // motion (flipped coords: y grows downward; pet position = top-left of the sprite)
    private var x: CGFloat = 0
    private var targetX: CGFloat = 0
    private var jumpY: CGFloat = 0
    private var vy: CGFloat = 0
    private var flip = false
    private var t: CGFloat = 0
    private var tick = 0
    private var walkFrame = 0
    private var altPose = false
    private var nextWander: CGFloat = 2
    private var nextBlink: CGFloat = 3
    private var blinkUntil: CGFloat = -1
    private var napUntil: CGFloat = -1
    private var nextNapCheck: CGFloat = 60
    private var zs: [(x: CGFloat, y: CGFloat, age: CGFloat)] = []

    private var spriteW: CGFloat { CGFloat(petSprite.cols) * px }
    private var spriteH: CGFloat { CGFloat(petSprite.rows) * px }
    private var floorY: CGFloat { bounds.height - (isPreview ? 4 : 10) }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        loadConfig()
        x = frame.width / 2 - spriteW / 2
        targetX = x
    }
    required init?(coder: NSCoder) { super.init(coder: coder); animationTimeInterval = 1.0 / 60.0; loadConfig() }

    override var isFlipped: Bool { true }
    override var hasConfigureSheet: Bool { false }

    // MARK: setup

    /// Pet choice and per-pet settings come from the app's own preferences.
    private func loadConfig() {
        let d = UserDefaults(suiteName: "com.soumil.pixelpet")
        let idx = max(0, min(PETS.count - 1, d?.integer(forKey: "petIndex") ?? 0))
        petSprite = PETS[idx]
        if let blob = d?.dictionary(forKey: "petSettings") as? [String: Data], let data = blob[petSprite.name], let s = PetSettings.decode(data) {
            cfg = s
        }
        px = isPreview ? 2 : CGFloat(cfg.pixelSize) * 1.5   // a little bigger than in the app: nothing else to look at
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        loadWallpaper()
    }

    private func loadWallpaper() {
        let screen = window?.screen ?? NSScreen.main
        guard let screen = screen, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        wallpaper = NSImage(contentsOf: url)
    }

    // MARK: animation

    override func startAnimation() { super.startAnimation() }
    override func stopAnimation() { super.stopAnimation() }

    override func animateOneFrame() {
        t += 1.0 / 60.0
        tick += 1
        let w = bounds.width
        let napping = t < napUntil
        var moving = false

        if !napping {
            if t >= nextWander {
                targetX = CGFloat.random(in: 16...max(17, w - spriteW - 16))
                if Bool.random() && jumpY == 0 { vy = CGFloat.random(in: 5...8) }
                nextWander = t + CGFloat.random(in: max(0.5, cfg.wanderMin)...max(1, cfg.wanderMax))
            }
            let dx = targetX - x
            if abs(dx) > 0.5 {
                let step = min(abs(dx), CGFloat(cfg.walkSpeed) * (abs(dx) > 400 ? 1.8 : 1.0))
                x += dx > 0 ? step : -step
                flip = dx < 0
                moving = true
            }
            if vy != 0 || jumpY > 0 {
                jumpY += vy
                vy -= CGFloat(cfg.gravity)
                if jumpY <= 0 { jumpY = 0; vy = 0 }
            }
            // sometimes it dozes off
            if t >= nextNapCheck {
                nextNapCheck = t + 60
                if !moving && jumpY == 0 && Double.random(in: 0..<1) < 0.5 { napUntil = t + CGFloat.random(in: 20...45) }
            }
        } else {
            if tick % 40 == 0 { zs.append((x + spriteW * (flip ? 0.2 : 0.8), floorY - spriteH - 4, 0)) }
        }
        zs = zs.compactMap { z in var z = z; z.age += 1; z.y -= 0.5; z.x += sin(z.age / 10) * 0.3; return z.age < 90 ? z : nil }

        if cfg.blink && t >= nextBlink { blinkUntil = t + 0.12; nextBlink = t + CGFloat.random(in: 2...5) }
        if jumpY > 0 { altPose = cfg.airPose && (tick / 7) % 2 == 1 }
        else if moving { altPose = false }
        else if cfg.idlePose { if tick % 45 == 0 { altPose.toggle() } }
        if moving { walkFrame += 1 }
        lastMoving = moving
        needsDisplay = true
    }
    private var lastMoving = false

    // MARK: drawing

    override func draw(_ rect: NSRect) {
        // wallpaper, aspect-fill; a quiet dark ground if it couldn't be read
        if let img = wallpaper, img.size.width > 0 {
            let s = max(bounds.width / img.size.width, bounds.height / img.size.height)
            let w = img.size.width * s, h = img.size.height * s
            img.draw(in: NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h), from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1).setFill()
            bounds.fill()
        }

        let napping = t < napUntil
        let blink = napping || t < blinkUntil
        let airborne = jumpY > 0
        let legs = airborne && cfg.airPose ? petSprite.legsAir : (lastMoving && cfg.walkAnim && (walkFrame / 8) % 2 == 0 ? petSprite.legsWalk : petSprite.legsStand)
        let base = altPose ? petSprite.bodyAlt : petSprite.body
        let body = blink ? base.map { $0.replacingOccurrences(of: "e", with: String(petSprite.bodyChar)) } : base
        let rows = body + legs

        let bob: CGFloat = (!airborne && !lastMoving && cfg.idleBob && !napping) ? -((sin(t * 4) + 1) * 1.0) : 0
        let breathe: CGFloat = napping ? (sin(t * 2) + 1) * 0.6 : 0
        let originY = floorY - spriteH - jumpY + bob + breathe

        NSGraphicsContext.saveGraphicsState()
        let tf = NSAffineTransform()
        tf.translateX(by: x, yBy: originY)
        if flip { tf.translateX(by: spriteW, yBy: 0); tf.scaleX(by: -1, yBy: 1) }
        tf.concat()
        for (ry, row) in rows.enumerated() {
            for (rx, c) in row.enumerated() {
                guard let color = petSprite.palette[c] else { continue }
                color.setFill()
                NSRect(x: CGFloat(rx) * px, y: CGFloat(ry) * px, width: px, height: px).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // sleepy z's
        for z in zs {
            let a = max(0, 1 - z.age / 90)
            let s = NSAttributedString(string: "z", attributes: [.font: NSFont.boldSystemFont(ofSize: 9 + z.age / 12), .foregroundColor: NSColor.white.withAlphaComponent(a * 0.9)])
            s.draw(at: NSPoint(x: z.x, y: z.y))
        }
    }
}
