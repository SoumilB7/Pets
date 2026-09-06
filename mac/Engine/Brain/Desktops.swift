import AppKit

// ENGINE-OWNED · Desktop travel.
// The pet lives on one desktop at a time. It leaves by walking off a screen edge
// and arrives on the other side; when you switch desktops it may come find you.

extension AppDelegate {
    // MARK: - desktops

    /// Move the pet to desktop `space`, entering from the left or right screen edge.
    func arrive(at space: UInt64, fromLeft: Bool) {
        petSpace = space
        let sc = mainScreen
        x = fromLeft ? sc.minX - SPRITE_W / 2 : sc.maxX - SPRITE_W / 2      // half on screen, walking in
        y = sc.minY
        vx = 0; vy = 0
        climb = nil; pendingJump = nil; pendingClimb = nil; pendingSpace = nil
        standing = platforms.first { $0.isFloor && $0.x1 <= sc.midX && sc.midX <= $0.x2 }
        targetX = fromLeft ? sc.minX + 160 : sc.maxX - SPRITE_W - 160
        lastIds = []                       // force a fresh scan log
        nextDesktopMove = Date().addingTimeInterval(S.desktopEvery * Double.random(in: 0.8...1.5))
        frontChanged = true
        nextWander = Date().addingTimeInterval(1.5)
        Log.w("space", "arrived on desktop \(space) from the \(fromLeft ? "left" : "right")\(space == userSpace ? " (where you are)" : "")")
    }

    /// Start walking to the screen edge that leads toward desktop `space`.
    func travelToSpace(_ space: UInt64) {
        let cur = Spaces.index(of: petSpace) ?? 0
        let dst = Spaces.index(of: space) ?? cur
        pendingDir = dst >= cur ? 1 : -1
        pendingSpace = space
        pendingJump = nil; pendingClimb = nil
        let sc = mainScreen
        targetX = pendingDir > 0 ? sc.maxX + 4 : sc.minX - SPRITE_W - 4
        Log.w("space", "leaving for desktop \(space) via the \(pendingDir > 0 ? "right" : "left") edge")
        if let here = standing, !here.isFloor {
            let edge = pendingDir > 0 ? sc.maxX : sc.minX
            if edge < here.x1 - 1 || edge > here.x2 + 1 {
                Log.w("space", "dropping off \(here.desc) to reach the edge")
                standing = nil; selfJump = true; vx = CGFloat(pendingDir) * 2; vy = 2
            }
        }
    }

}
