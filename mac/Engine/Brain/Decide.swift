import AppKit

// ENGINE-OWNED · Decisions.
// Every few seconds pickWanderTarget() chooses a destination using the user's
// percentages, the home zone and what actually exists right now; travel() / planJump()
// turn that into a hop, a climb, or a walk to a take-off point.

extension AppDelegate {
    // MARK: - deciding where to go

    /// Horizontal band the pet should keep to right now (home zone / avoid-centre), in screen x.
    func allowedBand(strict: Bool) -> ClosedRange<CGFloat> {
        let sc = screenAt(x)
        var lo = sc.minX, hi = sc.maxX
        if strict {
            let band = S.homeZone.xBand
            lo = sc.minX + sc.width * band.lowerBound
            hi = sc.minX + sc.width * band.upperBound
        }
        return lo...hi
    }

    /// Is this x-centre in the middle 40% of its screen?
    func inCenter(_ px: CGFloat) -> Bool {
        let sc = screenAt(px)
        return px > sc.minX + sc.width * 0.3 && px < sc.minX + sc.width * 0.7
    }

    /// Random standing x on `p`, preferring exposed spots inside `band`.
    func randomX(on p: Platform, band: ClosedRange<CGFloat>) -> CGFloat? {
        let lo = max(p.x1, band.lowerBound) + 10, hi = min(p.x2, band.upperBound) - 10
        guard hi > lo else { return nil }
        for _ in 0..<10 {
            let c = CGFloat.random(in: lo...hi)
            if exposed(p, at: c) && !(S.avoidCenter && inCenter(c) && Double.random(in: 0..<1) < 0.85) { return c - SPRITE_W / 2 }
        }
        return nil
    }

    func pickWanderTarget() {
        guard let here = standing else { return }
        let sc = screenAt(x)
        let m = mood
        let pinned = m.stayOnMainWindow
        if m.hopChance > 0, Double.random(in: 0..<1) < m.hopChance, !here.isFloor || true {
            vy = CGFloat.random(in: 6...9); selfJump = true; standing = nil; bounce = 0.25   // restless little hop
        }
        let strict = !pinned && S.homeZone != .anywhere && Double.random(in: 0..<1) < Double(S.stayHome) / 100
        let band = allowedBand(strict: strict)

        func usable(_ p: Platform) -> Bool {
            p.id != here.id && p.x2 > band.lowerBound && p.x1 < band.upperBound
        }
        let front = frontWindow.flatMap { usable($0) ? $0 : nil }
        let others = platforms.filter { !$0.isFloor && usable($0) && $0.id != frontWindow?.id }
        let floor = here.isFloor ? nil : floorUnder()
        let justSwitched = frontChanged
        frontChanged = false

        var dest: Platform? = nil
        var how = ""
        if pinned {
            dest = front                       // always head for the frontmost window
            how = front == nil ? "pinned but main window unusable/already here" : "pinned → main"
        } else if justSwitched, let f = front, Double.random(in: 0..<1) < Double(max(m.pMain, m.name == "focused" ? 0 : 50)) / 100 {
            dest = f                           // you switched windows: usually follow
            how = "focus changed → follow"
        } else {
            // weighted pick among destinations that exist right now
            var options: [(Double, Platform?)] = []
            if let f = front { options.append((Double(m.pMain), f)) }
            if let o = others.randomElement() { options.append((Double(m.pOther), o)) }
            if let fl = floor { options.append((Double(m.pFloor), fl)) }
            var otherSpace: UInt64? = nil
            if S.roamDesktops && Spaces.available && Date() >= nextDesktopMove && m.pSpace > 0 {
                otherSpace = Spaces.list().map { $0.id }.filter { $0 != petSpace }.randomElement()
                if otherSpace != nil { options.append((Double(m.pSpace), nil)) }   // marker: last nil = "another desktop"
            }
            let onYourWindow = frontWindow?.id == here.id
            let stay = m.name == "focused" && onYourWindow ? 1.0 : max(5, Double(100 - m.pMain - m.pOther - m.pFloor - (otherSpace != nil ? m.pSpace : 0)))
            options.append((stay, nil))   // when you're working and it's on your window, staying is nearly off the table
            var r = Double.random(in: 0..<1) * options.reduce(0) { $0 + $1.0 }
            var picked = options.count - 1
            for (i, o) in options.enumerated() { r -= o.0; if r <= 0 { picked = i; break } }
            dest = options[picked].1
            how = "weights " + options.enumerated().map { i, o in "\(Int(o.0)):\(o.1?.desc ?? (otherSpace != nil && i == options.count - 2 ? "desktop \(otherSpace!)" : "stay"))" }.joined(separator: " | ")
            if let sp = otherSpace, picked == options.count - 2 {
                Log.w("decide", "on \(here.desc) :: \(how) → desktop \(sp)")
                travelToSpace(sp)
                return
            }
        }
        Log.w("decide", "[\(m.name)] on \(here.desc) strict=\(strict) band=\(Log.f(band.lowerBound))-\(Log.f(band.upperBound)) front=\(frontWindow?.desc ?? "none") usableOthers=\(others.count) :: \(how) → \(dest?.desc ?? "wander along")")

        if let d = dest {
            if let tx = randomX(on: d, band: pinned ? allowedBand(strict: false) : band) {
                travel(to: d, targetX: tx)
                return
            }
            Log.w("decide", "no exposed spot on \(d.desc) inside band → wander along instead")
        }

        // wander along the current ledge, sometimes shyly toward the cursor
        var tx: CGFloat
        if Double.random(in: 0..<1) < Double(m.cursorCuriosity) / 100 {
            let m = NSEvent.mouseLocation
            let want = m.x - SPRITE_W / 2 + (m.x > x ? -50 : 50)
            tx = x + (want - x) * 0.5
        } else {
            tx = x + CGFloat.random(in: -220...220)
        }
        // if we're outside the home band, drift back toward it
        if strict && !band.contains(cx) {
            tx = (cx < band.lowerBound ? band.lowerBound + 40 : band.upperBound - 40) - SPRITE_W / 2
        }
        let lo = max(here.x1, band.lowerBound) - SPRITE_W / 2 + 6
        let hi = min(here.x2, band.upperBound) - SPRITE_W / 2 - 6
        if hi > lo { tx = min(hi, max(lo, tx)) }
        if S.avoidCenter && inCenter(tx + SPRITE_W / 2) && Double.random(in: 0..<1) < 0.85 {
            tx = cx < sc.midX ? sc.minX + sc.width * 0.25 - SPRITE_W / 2 : sc.minX + sc.width * 0.75 - SPRITE_W / 2
        }
        targetX = min(maxX, max(minX, tx))
    }

    /// Get to platform `p`: a hop if it's within jump height, otherwise walk to the
    /// nearer side edge of the window and climb it.
    func travel(to p: Platform, targetX tx: CGFloat) {
        let dh = p.top - y
        if p.isFloor || dh <= CGFloat(S.jumpHeight) {
            planJump(to: p, targetX: tx)
            return
        }
        let side = abs(p.x1 - cx) <= abs(p.x2 - cx) ? -1 : 1
        let edgeX = min(maxX, max(minX, side < 0 ? p.x1 - SPRITE_W + 6 : p.x2 - 6))
        pendingClimb = (p.id, side)
        pendingJump = nil
        targetX = edgeX
        Log.w("travel", "climb \(p.desc) via \(side < 0 ? "left" : "right") edge; walking from x=\(Log.f(x)) to x=\(Log.f(edgeX)) (dh=\(Log.f(dh)))")
        // if our current ledge doesn't extend to that edge, drop off toward it first
        if let here = standing, !here.isFloor {
            let c = edgeX + SPRITE_W / 2
            if c < here.x1 || c > here.x2 {
                Log.w("travel", "dropping off \(here.desc) toward that edge first")
                standing = nil
                selfJump = true
                vx = c < here.x1 ? -2 : 2
                vy = 2
            }
        }
    }

    /// Launch toward platform `p` landing near `tx`. If it's too far for one hop,
    /// walk to a take-off point first; `force` jumps anyway so we never loop.
    func planJump(to p: Platform, targetX tx: CGFloat, force: Bool = false) {
        let dx = tx - x
        let dh = p.top - y
        let g = CGFloat(S.gravity)
        let jvy = min(sqrt(2 * g * CGFloat(S.jumpHeight)), sqrt(2 * g * max(dh, 0)) + 4.5)
        let disc = jvy * jvy - 2 * g * dh
        let air = (jvy + sqrt(max(disc, 0))) / g
        let maxVx: CGFloat = 9
        if !force, abs(dx) / air > maxVx, let here = standing {
            let reach = maxVx * air * 0.9
            var walkTo = dx > 0 ? tx - reach : tx + reach
            let lo = here.x1 - SPRITE_W / 2 + 6, hi = here.x2 - SPRITE_W / 2 - 6
            walkTo = min(hi, max(lo, walkTo))
            targetX = walkTo
            pendingJump = p.id
            Log.w("travel", "hop to \(p.desc) too far (dx=\(Log.f(dx))); walking to take-off x=\(Log.f(walkTo))")
            return
        }
        vx = max(-maxVx, min(maxVx, dx / air))
        vy = jvy
        Log.w("travel", "hop to \(p.desc) dx=\(Log.f(dx)) dh=\(Log.f(dh)) vx=\(String(format: "%.1f", vx)) vy=\(String(format: "%.1f", vy))")
        bounce = 0.2
        standing = nil
        pendingJump = nil
        selfJump = true
        view.flip = vx < 0
    }

}
