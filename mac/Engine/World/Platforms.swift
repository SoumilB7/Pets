import AppKit

// ENGINE-OWNED · World model.
// Turns the on-screen window list into "platforms" (ledges) the pet can stand on,
// tracks which is the user's main window, and knows whether a ledge is covered.

/// A surface the pet can stand on: a screen floor or a window's top edge.
struct Platform: Equatable {
    let id: Int          // CG window number, or negative for a screen floor
    let x1: CGFloat
    let x2: CGFloat
    let top: CGFloat     // AppKit y of the surface
    let owner: String    // app name, for logs
    let pid: Int32       // owning process (0 for floors)
    var isFloor: Bool { id < 0 }
    var desc: String { isFloor ? "floor" : "\(owner)#\(id)[x \(Log.f(x1))-\(Log.f(x2)) top \(Log.f(top))]" }
}

extension AppDelegate {
    // MARK: - world scanning

    func floorUnder() -> Platform? { platforms.first { $0.isFloor && cx >= $0.x1 && cx <= $0.x2 } }

    /// True if the ledge `p` is actually visible at horizontal position `px`
    /// (no window in front covers the spot just above it).
    func exposed(_ p: Platform, at px: CGFloat) -> Bool {
        if p.isFloor { return true }
        let probe = NSPoint(x: px, y: p.top + 2)
        for w in winRects {
            if w.id == p.id { return true }          // reached ourselves: nothing in front covered it
            if w.rect.contains(probe) { return false }
        }
        return true
    }

    /// Is any part of this ledge uncovered? (cheap sampling, logs only)
    func exposedAnywhere(_ p: Platform, _ rects: [(id: Int, rect: NSRect)]) -> Bool {
        for i in 0...8 {
            let px = p.x1 + (p.x2 - p.x1) * CGFloat(i) / 8
            let probe = NSPoint(x: px, y: p.top + 2)
            var covered = false
            for w in rects { if w.id == p.id { break }; if w.rect.contains(probe) { covered = true; break } }
            if !covered { return true }
        }
        return false
    }

    func refreshPlatforms() {
        if Date().timeIntervalSince(lastSpaceChange) < 0.6 { return }   // mid-switch: window list is garbage
        var list: [Platform] = []
        var rects: [(id: Int, rect: NSRect)] = []
        var front: Platform? = nil
        let primaryH = NSScreen.screens.first?.frame.height ?? 900

        if S.walkOnWindows,
           let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for w in info {
                guard (w[kCGWindowLayer as String] as? Int) == 0,
                      (w[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                      ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.1,
                      let num = w[kCGWindowNumber as String] as? Int,
                      let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                      let bx = b["X"], let by = b["Y"], let bw = b["Width"], let bh = b["Height"],
                      bw >= 140, bh >= 80 else { continue }
                let rect = NSRect(x: bx, y: primaryH - by - bh, width: bw, height: bh)
                if !screens.contains(where: { $0.midX - $0.width <= rect.midX && rect.midX <= $0.midX + $0.width }) { return }  // Mission Control layout: ignore this scan
                rects.append((num, rect))
                var top = rect.maxY
                let sc = screenAt(bx + bw / 2)
                if top > sc.maxY - SPRITE_H { top = sc.maxY - SPRITE_H }   // flush with menu bar: stand on the title bar
                if top < sc.minY + 10 { continue }
                let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
                let p = Platform(id: num, x1: bx, x2: bx + bw, top: top, owner: owner, pid: (w[kCGWindowOwnerPID as String] as? Int32) ?? 0)
                if front == nil { front = p }                                // list is front-to-back
                list.append(p)
            }
        }
        for (i, s) in screens.enumerated() {
            list.append(Platform(id: -(i + 1), x1: s.minX, x2: s.maxX, top: s.minY, owner: "screen\(i)", pid: 0))
        }

        let ids = Set(list.map { $0.id })
        if ids != lastIds {
            lastIds = ids
            let visible = list.filter { !$0.isFloor }.map { p in
                "\(p.desc)\(exposedAnywhere(p, rects) ? "" : " (covered)")"
            }
            Log.w("scan", "\(visible.count) ledges: " + (visible.isEmpty ? "none" : visible.joined(separator: "; ")))
        }
        // you switched to another window: re-decide soon (see pickWanderTarget)
        if front?.id != lastFrontId {
            lastFrontId = front?.id
            Log.w("front", front.map { "now \($0.desc)" } ?? "none")
            if front != nil && tickCount > 60 {
                frontChanged = true
                nextWander = min(nextWander, Date().addingTimeInterval(0.8))
            }
        }
        if let c = climb, !list.contains(where: { $0.id == c.id }) { climb = nil }   // window closed mid-climb

        // ride the window we're standing on; fall if it vanished
        if let s = standing, !s.isFloor {
            if let n = list.first(where: { $0.id == s.id }) {
                if n != s {
                    x += n.x1 - s.x1
                    targetX += n.x1 - s.x1
                    y = n.top
                    standing = n
                }
            } else {
                Log.w("fall", "ledge \(s.desc) vanished")
                standing = nil
            }
        }
        platforms = list
        winRects = rects
        frontWindow = front
    }

}
