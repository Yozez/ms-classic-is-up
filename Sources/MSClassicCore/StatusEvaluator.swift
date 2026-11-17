import Foundation

public enum StatusEvaluator {
    /// How long past the announced end we keep reporting "overrunning" before assuming it's over.
    public static let overrunGrace: TimeInterval = 6 * 3600
    /// Notices without an end time count as active for at most this long after they start.
    public static let openEndedLimit: TimeInterval = 24 * 3600

    public static func evaluate(_ notices: [MaintenanceNotice], now: Date) -> StatusSnapshot {
        let pending = notices.filter { !$0.isCompleted }

        let next = pending
            .filter { $0.start > now }
            .min { $0.start < $1.start }

        let active = pending
            .filter { n in
                guard n.start <= now else { return false }
                if let end = n.end { return now < end }
                return now < n.start.addingTimeInterval(openEndedLimit)
            }
            .min { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
        if let active {
            return StatusSnapshot(state: .maintenance, current: active, next: next)
        }

        let overrun = pending
            .filter { n in
                guard let end = n.end else { return false }
                return now >= end && now < end.addingTimeInterval(overrunGrace)
            }
            .max { $0.end! < $1.end! }
        if let overrun {
            return StatusSnapshot(state: .overrunning, current: overrun, next: next)
        }

        return StatusSnapshot(state: .up, current: nil, next: next)
    }
}
