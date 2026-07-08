import Foundation

struct TapSequenceCounter {
    private(set) var count = 0
    private(set) var lastTapTime: TimeInterval = 0

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

