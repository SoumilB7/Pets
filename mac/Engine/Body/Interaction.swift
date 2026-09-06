import AppKit

// ENGINE-OWNED · Mouse interaction and impacts.
// grab / drag / release come from PetView; bonk() is the one gate for dizziness.

enum Impact { case ceiling, wall, floor }

extension AppDelegate {
    // MARK: - interaction (called from PetView)

    func grab() {
        guard S.throwable || S.clickHop else { return }
        held = true
        dragged = false
        vx = 0; vy = 0
        petMeter = 0
        holdStart = Date()
        standing = nil
        pendingJump = nil
        pendingClimb = nil
        pendingSpace = nil
        climb = nil
        selfJump = false
        let m = NSEvent.mouseLocation
        grabOffset = NSPoint(x: m.x - x, y: m.y - y)
        lastPos = NSPoint(x: x, y: y)
        velSamples.removeAll()
    }

    func drag() {
        guard held, S.throwable else { return }
        dragged = true
        let m = NSEvent.mouseLocation
        x = m.x - grabOffset.x
        y = m.y - grabOffset.y
    }

    func release(click: Bool) {
        guard held else { return }
        held = false
        if click {
            bounce = 0.3
            if S.clickHop && !isDizzy { vy = 9; selfJump = true }
        } else {
            let heldFor = CGFloat(Date().timeIntervalSince(holdStart))
            bounce = S.holdAffectsBounce ? min(0.92, CGFloat(S.bounciness) * 0.7 + heldFor * 0.2) : CGFloat(S.bounciness)
            let n = CGFloat(max(velSamples.count, 1))
            vx = velSamples.reduce(0) { $0 + $1.x } / n
            vy = velSamples.reduce(0) { $0 + $1.y } / n
            vx = max(-45, min(45, vx))
            vy = max(-45, min(45, vy))
            Log.w("throw", "vx=\(Log.f(vx)) vy=\(Log.f(vy)) held \(String(format: "%.1f", heldFor))s bounce=\(String(format: "%.2f", bounce))")
        }
        scheduleWander()
    }

    /// Dizziness rules live here so every collision goes through one gate.
    func bonk(_ kind: Impact, _ speed: CGFloat) {
        switch S.dizzyMode {
        case .never: return
        case .ceilingOnly: guard kind == .ceiling else { return }
        case .anyHardHit: if selfJump && kind != .ceiling { return }   // our own hops never hurt
        }
        if speed > 11 { dizzyUntil = Date().addingTimeInterval(S.dizzySeconds); Log.w("impact", "\(kind) at speed \(Log.f(speed)) → dizzy") }
    }

    func scheduleWander(soon: Bool = false) {
        let lo = S.wanderMin, hi = max(S.wanderMax, S.wanderMin)
        var r = mood.stayOnMainWindow ? Double.random(in: 1.5...max(1.5, hi / 2)) : Double.random(in: lo...hi)
        r = max(0.4, r * mood.wanderScale)
        nextWander = Date().addingTimeInterval(soon ? 1.0 : r)
    }

}
