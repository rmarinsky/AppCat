import Foundation

/// Formats a time interval (in seconds) as a short string —
/// `12s`, `4m 12s`, `2h 17m`, `1d 3h`. Used by stats UI and menu bar teaser.
/// The unit suffixes (`s`, `m`, `h`, `d`) are internationally understood, so this
/// helper deliberately doesn't localize them.
enum TimeSavedFormatter {
    static func short(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 {
            let remSec = seconds % 60
            return remSec == 0 ? "\(minutes)m" : "\(minutes)m \(remSec)s"
        }
        let hours = minutes / 60
        if hours < 24 {
            let remMin = minutes % 60
            return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days)d" : "\(days)d \(remHours)h"
    }

    /// Compact form for the menu bar teaser — drops the seconds bit when minutes > 0.
    static func teaser(seconds: Int) -> String {
        let seconds = max(0, seconds)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours)h" : "\(hours)h \(remMin)m"
    }

    /// Single big-unit hero form: returns the rounded value and its unit label,
    /// e.g. `(value: "3.4", unit: "hrs")`. Used by the Overview hero number.
    static func hero(seconds: Int) -> (value: String, unit: String) {
        let s = max(0, seconds)
        if s >= 3600 {
            let hrs = Double(s) / 3600.0
            return (String(format: hrs >= 10 ? "%.0f" : "%.1f", hrs), String(localized: "hrs"))
        }
        if s >= 60 {
            return ("\(s / 60)", String(localized: "min"))
        }
        return ("\(s)", String(localized: "sec"))
    }
}
