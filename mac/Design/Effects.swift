import AppKit

// DESIGN-OWNED. Small decorative overlays the engine asks for.
// The function SIGNATURES are part of the contract: keep them, change the insides freely.
// All drawing happens in a flipped coordinate space (y grows DOWNWARD), in points.

enum Effects {
    /// Colour of hearts that float up while the pet is being petted.
    static let heartColor = rgb(1.0, 0.35, 0.5)
    static let heartLight = rgb(1.0, 0.72, 0.80)
    static let heartDark  = rgb(0.75, 0.15, 0.32)

    /// Colour of the stars that orbit a dizzy pet's head.
    static let starColor = rgb(1.0, 0.85, 0.2)
    static let starCore  = rgb(1.0, 0.97, 0.75)

    /// One floating heart. `origin` is the heart's top-left in points.
    /// `alpha` fades 1 → 0 over the heart's life (~1.2 s).
    /// Pixel heart with a highlight and a darker underside so it pops on any wallpaper.
    static func drawHeart(origin: NSPoint, alpha: CGFloat) {
        let s: CGFloat = 2.5
        // h = highlight, o = body, d = dark bottom edge
        let shape = [".oo.oo.", "ohooooo", "ooooooo", ".ooooo.", "..ddd..", "...d..."]
        for (ry, row) in shape.enumerated() {
            for (rx, c) in row.enumerated() where c != "." {
                switch c {
                case "h": heartLight.withAlphaComponent(alpha).setFill()
                case "d": heartDark.withAlphaComponent(alpha).setFill()
                default:  heartColor.withAlphaComponent(alpha).setFill()
                }
                NSRect(x: origin.x + CGFloat(rx) * s, y: origin.y + CGFloat(ry) * s, width: s, height: s).fill()
            }
        }
    }

    /// Stars orbiting a point. `center` is in GRID units (col, row) relative to the
    /// pet's body grid; negative rows are above the head. `angle` advances every
    /// frame so the stars spin. `px` is the size of one grid pixel in points.
    /// Three four-point sparkles that shrink as they pass "behind" the head.
    static func drawStars(center: (x: CGFloat, y: CGFloat), angle: CGFloat, px: CGFloat) {
        for i in 0..<3 {
            let a = angle + CGFloat(i) * 2.094
            let depth = (sin(a) + 1) / 2                     // 0 = back, 1 = front
            let sx = center.x + cos(a) * 4.5, sy = center.y + sin(a) * 1.4
            let s = px * (0.5 + 0.4 * depth)
            let bx = sx * px, by = sy * px
            starColor.withAlphaComponent(0.55 + 0.45 * depth).setFill()
            NSRect(x: bx - s * 1.5, y: by - s * 0.5, width: s * 4, height: s).fill()
            NSRect(x: bx, y: by - s * 2, width: s, height: s * 4).fill()
            starCore.withAlphaComponent(0.55 + 0.45 * depth).setFill()
            NSRect(x: bx, y: by - s * 0.5, width: s, height: s).fill()
        }
    }

    /// Eye overlays drawn on top of the sprite at each `PetSprite.eyes` entry.
    /// `plot(col, row)` fills one grid pixel in the pet's eye colour.
    static func drawHappyEye(col ex: CGFloat, row ey: CGFloat, plot: (CGFloat, CGFloat) -> Void) {
        plot(ex - 1, ey); plot(ex, ey - 1); plot(ex + 1, ey)          // a little ^
    }
    static func drawDizzyEye(col ex: CGFloat, row ey: CGFloat, plot: (CGFloat, CGFloat) -> Void) {
        plot(ex - 1, ey - 1); plot(ex + 1, ey - 1); plot(ex, ey)      // an X
        plot(ex - 1, ey + 1); plot(ex + 1, ey + 1)
    }
}
