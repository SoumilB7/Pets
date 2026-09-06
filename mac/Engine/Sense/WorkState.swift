import Foundation

// ENGINE-OWNED · Are you working on one of your notes right now, or drifting?
// Evaluated once a second from: the current window's best note score (State Space),
// the window's category, and how long the reading has held (hysteresis + dwell).

enum WorkState: String { case neutral, onTask, offTask, away }

struct WorkReading {
    var state: WorkState
    var taskTitle: String      // when onTask
    var score: Float
    var since: Date            // when this state began
    var reason: String
}

final class WorkStateDetector {
    private(set) var current = WorkReading(state: .neutral, taskTitle: "", score: 0, since: Date(), reason: "start")
    private var candidate: WorkState = .neutral
    private var candidateSince = Date()
    private var candidateTitle = ""
    private var candidateScore: Float = 0
    private var candidateReason = ""

    /// Feed one reading. Returns the new state if it changed.
    @discardableResult
    func evaluate(context: ScreenContext, now: NowInfo?, openTasks: Int, threshold: Float, s: PetSettings) -> WorkState? {
        var raw: WorkState = .neutral
        var title = "", score: Float = 0, reason = ""
        if context.category == .away {
            raw = .away; reason = "lock screen"
        } else if openTasks == 0 {
            raw = .neutral; reason = "no open notes"
        } else if let n = now, let best = n.tasks.first {
            score = best.score; title = best.title
            if best.score >= threshold {
                raw = .onTask; reason = "“\(best.title)” \(String(format: "%.2f", best.score))"
            } else {
                let cat = context.category.rawValue
                let distraction = s.distractionCategories.contains(cat)
                let weak = best.score < threshold * 0.75 && ["browser", "chat", "other", "unknown", "media", "social"].contains(cat)
                if distraction || weak || s.strictOffTask {
                    raw = .offTask; reason = "\(context.app) [\(cat)], best note \(String(format: "%.2f", best.score))"
                } else {
                    raw = .neutral; reason = "\(context.app) [\(cat)] work-adjacent, best \(String(format: "%.2f", best.score))"
                }
            }
        } else {
            raw = .neutral; reason = "no capture yet"
        }

        if raw != candidate {
            candidate = raw; candidateSince = Date()
        }
        candidateTitle = title; candidateScore = score; candidateReason = reason
        let held = Date().timeIntervalSince(candidateSince)
        let needed: Double
        switch candidate {
        case .offTask: needed = s.distractDwell          // don't nag over a quick look
        case .onTask: needed = 4
        case .away: needed = 0
        case .neutral: needed = 8
        }
        guard candidate != current.state, held >= needed else { return nil }
        current = WorkReading(state: candidate, taskTitle: candidateTitle, score: candidateScore, since: Date(), reason: candidateReason)
        return candidate
    }

    var summary: String {
        let mins = Int(Date().timeIntervalSince(current.since)) / 60
        let dur = mins > 0 ? " for \(mins) min" : ""
        switch current.state {
        case .onTask: return "On task: \(current.taskTitle)\(dur)"
        case .offTask: return "Off task\(dur) · \(current.reason)"
        case .away: return "Away"
        case .neutral: return "Neutral · \(current.reason)"
        }
    }
}
