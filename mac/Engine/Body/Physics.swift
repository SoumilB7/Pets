import AppKit

// ENGINE-OWNED · The 60 Hz tick.
// Order inside tick(): mode gate → desktops → mouse → held / climbing / airborne /
// skidding / dizzy-or-petted / walking → eyes → hearts → frame selection → draw.

extension AppDelegate {
    func tickChill() {
        let sc = mainScreen
        let seq = PET_EXTRAS[pet.name]?.coffee
        let frames = seq?.frames ?? [pet.body + pet.legsStand]
        let fps = seq?.fps ?? 1
        let f = frames[Int(t * CGFloat(fps)) % max(1, frames.count)]
        let cols = CGFloat(f.first?.count ?? pet.cols), rows = CGFloat(f.count)
        let w = cols * PX, h = rows * PX + BOB_PAD + TOP_PAD
        if window.frame.width != w || window.frame.height != h {
            window.setContentSize(NSSize(width: w, height: h))
            view.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }
        view.palette = pet.palette.merging(PET_EXTRAS[pet.name]?.palette ?? [:]) { _, b in b }
        view.overlays = false
        view.rows = f
        view.flip = seq == nil          // no scene: at least face left, toward the screen
        view.yOffset = 0
        view.eyes = .open
        x = sc.maxX - w - 12
        y = sc.minY
        standing = nil
        window.ignoresMouseEvents = true
        if !window.isVisible { window.orderFrontRegardless() }
        window.setFrameOrigin(NSPoint(x: x, y: y))
        view.needsDisplay = true
    }

    // MARK: - per-frame update

    func tick() {
        let now = Date()
        t += 1.0 / 60.0
        tickCount += 1
        if tickCount % 600 == 0 && mode == .normal { logPosition() }   // position heartbeat every 10 s
        if !petEnabled {                       // switched off: nothing on screen, nothing to do
            if window.isVisible { window.orderOut(nil) }
            return
        }
        switch mode {
        case .action:
            if window.isVisible { window.orderOut(nil) }
            return
        case .chill:
            tickChill()
            return
        case .normal:
            break
        }
        // ---- desktops: where are you, where is the pet ----
        if Spaces.available && tickCount % 6 == 0 {
            let a = Spaces.active()
            if a != userSpace {
                userSpace = a
                lastSpaceChange = now
                Log.w("space", "you switched to desktop \(a); pet is on \(petSpace)\(petSpace == a ? " (same)" : "")")
                if petSpace != a { nextDesktopMove = max(nextDesktopMove, now.addingTimeInterval(min(S.desktopEvery, 8))) }   // a moment before it comes looking
                if S.stayOnMainWindow && petSpace != a {
                    let ci = Spaces.index(of: petSpace) ?? 0, ui = Spaces.index(of: a) ?? 0
                    arrive(at: a, fromLeft: ui >= ci)
                }
            }
        }
        let onUserSpace = !Spaces.available || petSpace == userSpace
        if onUserSpace, !window.isVisible { window.orderFrontRegardless() }
        if !onUserSpace, window.isVisible { window.orderOut(nil) }
        if !onUserSpace {
            // The pet is on another desktop. It waits there; every so often it decides to come find you.
            if now >= nextDesktopMove {
                nextDesktopMove = now.addingTimeInterval(S.desktopEvery * Double.random(in: 0.8...1.5))
                if Double.random(in: 0..<1) < Double(S.returnToMe) / 100 {
                    let ci = Spaces.index(of: petSpace) ?? 0, ui = Spaces.index(of: userSpace) ?? 0
                    Log.w("space", "coming to find you on desktop \(userSpace)")
                    arrive(at: userSpace, fromLeft: ui >= ci)
                } else {
                    Log.w("space", "staying on desktop \(petSpace) for now (you are on \(userSpace))")
                }
            }
            return
        }

        if tickCount % 6 == 0 { refreshPlatforms() }
        var moving = false

        // ---- mouse: only the sprite itself is clickable; rubbing it = petting ----
        let m = NSEvent.mouseLocation
        let over = NSRect(x: x, y: y, width: SPRITE_W, height: SPRITE_H).contains(m)
        window.ignoresMouseEvents = !(over || held)
        if over && !held && S.petting { petMeter = min(90, petMeter + abs(m.x - lastMouse.x) + abs(m.y - lastMouse.y)) }
        lastMouse = m
        petMeter = max(0, petMeter - 1.2)

        if held {
            let p = NSPoint(x: x, y: y)
            velSamples.append(NSPoint(x: p.x - lastPos.x, y: p.y - lastPos.y))
            if velSamples.count > 5 { velSamples.removeFirst() }
            lastPos = p
            if abs(velSamples.last?.x ?? 0) > 0.5 { view.flip = (velSamples.last!.x) < 0 }
        } else if let c = climb {
            // ---- climbing a window's side edge ----
            if let p = platforms.first(where: { $0.id == c.id }) {
                x = c.side < 0 ? p.x1 - SPRITE_W + 6 : p.x2 - 6
                x = min(maxX, max(minX, x))
                y += CGFloat(S.walkSpeed) * 1.6
                view.flip = c.side > 0
                if y >= p.top {
                    y = p.top
                    standing = p
                    climb = nil
                    Log.w("arrive", "climbed onto \(p.desc)")
                    x = min(maxX, max(minX, c.side < 0 ? p.x1 + 6 : p.x2 - SPRITE_W - 6))
                    targetX = randomX(on: p, band: allowedBand(strict: false)) ?? x
                    scheduleWander()
                }
            } else {
                climb = nil
            }
            moving = true
        } else if standing == nil {
            // ---- airborne ----
            let prevY = y
            let g = CGFloat(S.gravity)
            vy -= g
            x += vx
            y += vy
            if x < minX { x = minX; bonk(.wall, abs(vx)); vx = -vx * bounce }
            if x > maxX { x = maxX; bonk(.wall, abs(vx)); vx = -vx * bounce }
            if y > ceilY { y = ceilY; bonk(.ceiling, abs(vy)); vy = -vy * bounce * 0.8 }

            if vy <= 0 {
                let hit = platforms
                    .filter { cx >= $0.x1 && cx <= $0.x2 && prevY >= $0.top - 0.01 && y <= $0.top && exposed($0, at: cx) }
                    .max { $0.top < $1.top }
                if let p = hit {
                    y = p.top
                    bonk(.floor, abs(vy))
                    if abs(vy) > 2.5 && bounce > 0.25 {
                        vy = -vy * bounce
                        vx *= 0.6 + bounce * 0.35
                    } else {
                        vy = 0
                        standing = p
                        selfJump = false
                        Log.w("arrive", "landed on \(p.desc) at x=\(Log.f(x))\(pendingClimb != nil ? " (continuing to climb)" : "")")
                        if pendingClimb == nil && pendingJump == nil && pendingSpace == nil { targetX = x }
                        vx = abs(vx) > 3 ? vx * 0.5 : 0
                    }
                }
            }
            if y < floorY { y = floorY; vy = 0; standing = floorUnder(); selfJump = false; Log.w("arrive", "hit the floor at x=\(Log.f(x))") }
            if abs(vx) > 0.5 { view.flip = vx < 0 }
            moving = true
        } else if let here = standing, abs(vx) > 0.3 {
            // ---- skidding after a landing ----
            x += vx
            vx *= 0.85
            if abs(vx) < 0.3 { vx = 0; if pendingClimb == nil && pendingSpace == nil { targetX = x } }
            if cx < here.x1 || cx > here.x2 { standing = nil }
            if x < minX { x = minX; vx = -vx * bounce }
            if x > maxX { x = maxX; vx = -vx * bounce }
            moving = true
        } else if isDizzy || isPetting {
            targetX = x
            nextWander = max(nextWander, now.addingTimeInterval(1.5))
        } else if let here = standing {
            // ---- walking ----
            if now >= nextWander && pendingJump == nil && pendingClimb == nil && pendingSpace == nil {
                pickWanderTarget()
                scheduleWander()
            }
            let dx = targetX - x
            if abs(dx) > 0.5 {
                let base = CGFloat(S.walkSpeed)
                let step = min(abs(dx), abs(dx) > 400 ? base * 1.8 : base)
                x += dx > 0 ? step : -step
                view.flip = dx < 0
                moving = true
                if let sp = pendingSpace {
                    let sc = mainScreen
                    let gone = pendingDir > 0 ? cx >= sc.maxX : cx <= sc.minX          // half the sprite is off screen
                    if gone { arrive(at: sp, fromLeft: pendingDir > 0); return }
                    if !here.isFloor && (cx < here.x1 - 4 || cx > here.x2 + 4) { standing = nil }   // ledge ends short of the screen edge: drop
                } else if cx < here.x1 || cx > here.x2 { Log.w("fall", "walked off \(here.desc)"); standing = nil; pendingJump = nil }
            } else if let pc = pendingClimb {
                pendingClimb = nil
                if platforms.contains(where: { $0.id == pc.id }) { Log.w("travel", "start climbing #\(pc.id)"); climb = pc; standing = nil }
                else { Log.w("travel", "wanted to climb #\(pc.id) but it is gone") }
            } else if let pj = pendingJump {
                pendingJump = nil
                if let p = platforms.first(where: { $0.id == pj }),
                   let tx = randomX(on: p, band: allowedBand(strict: false)) {
                    planJump(to: p, targetX: tx, force: true)
                }
            }
            if let s = standing { y = s.top }
        }

        // ---- eyes ----
        if S.blink && now >= nextBlink {
            blinkUntil = now.addingTimeInterval(0.12)
            nextBlink = now.addingTimeInterval(Double.random(in: 2...5))
        }
        let eyes: Eyes
        if isDizzy { eyes = .dizzy }
        else if isPetting { eyes = .happy }
        else if S.blink && now < blinkUntil { eyes = .blink }
        else { eyes = .open }

        // ---- hearts ----
        if isPetting && S.hearts {
            heartTimer += 1
            if heartTimer % 18 == 0 {
                view.hearts.append(Heart(x: CGFloat.random(in: 8...max(9, WIN_W - 20)), y: TOP_PAD + 6, age: 0))
            }
        }
        view.hearts = view.hearts.compactMap { h in
            var h = h; h.age += 1; h.y -= 0.6; h.x += sin(h.age / 8) * 0.4
            return h.age < 70 ? h : nil
        }

        // ---- frame selection ----
        let airborne = held || (standing == nil && climb == nil)
        let legs: [String]
        if airborne && S.airPose {
            legs = pet.legsAir
        } else if moving && S.walkAnim && !airborne {
            walkFrame += 1
            legs = (walkFrame / 8) % 2 == 0 ? pet.legsWalk : pet.legsStand
        } else {
            legs = pet.legsStand
        }
        altTimer += 1
        if airborne { altPose = S.airPose && (altTimer / 7) % 2 == 1 }
        else if moving { altPose = false }
        else if S.idlePose { if altTimer % 45 == 0 { altPose.toggle() } }
        else { altPose = false }
        view.rows = spriteRows(alt: altPose, legs: legs, eyes: eyes)
        view.eyes = eyes
        view.starAngle = t * 7
        if isDizzy {
            view.yOffset = sin(t * 12) * 1.0
        } else {
            view.yOffset = (S.idleBob && !airborne && !moving) ? -((sin(t * 4) + 1) * 1.0) : 0
        }

        lastMoving = moving
        window.setFrameOrigin(NSPoint(x: x, y: y))
        view.needsDisplay = true
    }
}
