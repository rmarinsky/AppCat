import Foundation

struct TapSequenceCounter {
    private(set) var count = 0
    private(set) var lastTapTime: TimeInterval = 0

    /// True while a multi-tap sequence is already underway and still within `interval`.
    func isSequenceInProgress(at now: TimeInterval, interval: TimeInterval) -> Bool {
        count > 0 && (now - lastTapTime) <= interval
    }

    mutating func registerTap(at now: TimeInterval, requiredCount: Int, interval: TimeInterval) -> Bool {
        if now - lastTapTime > interval {
            count = 0
        }

        count += 1
        lastTapTime = now

        guard count >= max(1, requiredCount) else {
            return false
        }

        reset()
        return true
    }

    mutating func reset() {
        count = 0
        lastTapTime = 0
    }
}

