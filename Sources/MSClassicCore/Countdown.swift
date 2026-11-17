import Foundation

public enum Countdown {
    /// Longest span we format; anything beyond (including infinite dates) shows as "999d+".
    static let maxMinutes = 999 * 1440

    /// "2h 14m", "1d 2h", "5m". Never traps, whatever the dates are.
    public static func format(to target: Date, from now: Date) -> String {
        let seconds = target.timeIntervalSince(now)
        guard seconds.isFinite || seconds == .infinity else { return "0m" } // NaN
        let minutes = (seconds / 60).rounded(.up)
        guard minutes > 0 else { return "0m" }
        guard minutes < Double(maxMinutes) else { return "999d+" }
        let total = Int(minutes)
        let days = total / 1440, hours = (total % 1440) / 60, mins = total % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%dh %02dm", hours, mins) }
        return "\(mins)m"
    }
}
