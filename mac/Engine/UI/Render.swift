import AppKit

// ENGINE-OWNED. Turns a PetSprite + animation state into pixels on screen.
// Design agents should not need to touch this. If a new kind of overlay is
// wanted, add a hook in Design/Effects.swift and call it from draw() here.

/// Currently selected pet. Set by the menu / preferences; read everywhere.
var pet: PetSprite = PETS[Settings.shared.petIndex]

enum Eyes { case open, blink, happy, dizzy }

/// Full row list (body + legs) for one frame.
func spriteRows(alt: Bool, legs: [String], eyes: Eyes) -> [String] {
    let base = alt ? pet.bodyAlt : pet.body
    let body = eyes == .open ? base : base.map { $0.replacingOccurrences(of: "e", with: String(pet.bodyChar)) }
    return body + legs
}

/// Size of one sprite pixel on screen, in points (a per-pet setting).
var PX: CGFloat { CGFloat(S.pixelSize) }
var SPRITE_W: CGFloat { CGFloat(pet.cols) * PX }
var SPRITE_H: CGFloat { CGFloat(pet.rows) * PX }
let BOB_PAD: CGFloat = 4     // room below for the idle bob
let TOP_PAD: CGFloat = 36    // room above the head for stars / hearts
var WIN_W: CGFloat { SPRITE_W }
var WIN_H: CGFloat { SPRITE_H + BOB_PAD + TOP_PAD }

struct Heart { var x: CGFloat; var y: CGFloat; var age: CGFloat }

// ---- View ----
final class PetView: NSView {
    var rows: [String] = spriteRows(alt: false, legs: pet.legsStand, eyes: .open)
    var palette: [Character: NSColor] = pet.palette   // swapped for scene frames (chill mode)
    var overlays = true                                // eye overlays + stars
    var eyes: Eyes = .open
    var flip = false                // true = facing left
    var yOffset: CGFloat = 0        // idle bob / dizzy wobble, in points (negative = up)
    var starAngle: CGFloat = 0
    var hearts: [Heart] = []
    weak var delegate: AppDelegate?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Fill one grid pixel (sprite grid coordinates).
    func px(_ x: CGFloat, _ y: CGFloat) {
        NSRect(x: x * PX, y: y * PX, width: PX, height: PX).fill()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // hearts live in window space and are never mirrored
        for h in hearts {
            Effects.drawHeart(origin: NSPoint(x: h.x, y: h.y), alpha: max(0, 1 - h.age / 70))
        }

        ctx.saveGState()
        ctx.translateBy(x: 0, y: TOP_PAD + BOB_PAD + yOffset)
        if flip {
            ctx.translateBy(x: CGFloat(rows.first?.count ?? 0) * PX, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        for (y, row) in rows.enumerated() {
            for (x, c) in row.enumerated() {
                guard let color = palette[c] else { continue }
                color.setFill()
                px(CGFloat(x), CGFloat(y))
            }
        }
        guard overlays else { ctx.restoreGState(); return }
        pet.eyeColor.setFill()
        for e in pet.eyes {
            let ex = CGFloat(e.col), ey = CGFloat(e.row)
            switch eyes {
            case .happy: Effects.drawHappyEye(col: ex, row: ey, plot: px)
            case .dizzy: Effects.drawDizzyEye(col: ex, row: ey, plot: px)
            default: break
            }
        }
        if eyes == .dizzy {
            Effects.drawStars(center: (CGFloat(pet.cols) * 0.6, -3), angle: starAngle, px: PX)
        }
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) { delegate?.grab() }
    override func mouseDragged(with event: NSEvent) { delegate?.drag() }
    override func mouseUp(with event: NSEvent) { delegate?.release(click: delegate?.dragged == false) }
}
