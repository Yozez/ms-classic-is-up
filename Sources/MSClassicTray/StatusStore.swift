import AppKit
import MSClassicCore
import Observation

@Observable
@MainActor
final class StatusStore {
    private(set) var notices: [MaintenanceNotice] = []
    private(set) var snapshot: StatusSnapshot = .unknown
    private(set) var lastChecked: Date?
    private(set) var lastError: String?
    private(set) var isRefreshing = false
    /// Updated every tick so countdowns re-render without a network call.
    private(set) var now: Date

    static let pollInterval: Duration = .seconds(120)
    static let tickInterval: Duration = .seconds(15)
    /// Show the "in Xh Ym" countdown in the menu bar when maintenance starts within this window.
    static let countdownHorizon: TimeInterval = 24 * 3600

    private let client = NexonClient()
    private let clock: AppClock
    private var started = false
    private var hasData = false

    init() {
        clock = AppClock.fromEnvironment()
        now = clock.now
    }

    func start() {
        guard !started else { return }
        started = true

        Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            apply(try await client.fetchClassicMaintenance(now: clock.now))
        } catch {
            lastError = error.localizedDescription
            tick()
        }
    }

    /// Replaces the notices with freshly fetched ones and re-evaluates.
    func apply(_ fetched: [MaintenanceNotice]) {
        notices = fetched
        hasData = true
        lastError = nil
        lastChecked = clock.now
        tick()
    }

    private func tick() {
        now = clock.now
        snapshot = hasData ? StatusEvaluator.evaluate(notices, now: now) : .unknown
    }

    // MARK: - Presentation helpers

    var menuBarCountdown: String? {
        switch snapshot.state {
        case .maintenance:
            guard let end = snapshot.current?.end else { return nil }
            return "ends \(Self.countdown(to: end, from: now))"
        case .overrunning:
            guard let end = snapshot.current?.end else { return nil }
            return "late \(Self.countdown(to: now, from: end))"
        case .up:
            guard let next = snapshot.next, next.start.timeIntervalSince(now) <= Self.countdownHorizon else { return nil }
            return "in \(Self.countdown(to: next.start, from: now))"
        case .unknown:
            return nil
        }
    }

    static func countdown(to target: Date, from now: Date) -> String {
        Countdown.format(to: target, from: now)
    }
}

/// Wall clock, optionally shifted via `MSC_NOW=<ISO8601>` for testing states.
struct AppClock {
    let offset: TimeInterval

    var now: Date { Date().addingTimeInterval(offset) }

    static func fromEnvironment() -> AppClock {
        guard let value = ProcessInfo.processInfo.environment["MSC_NOW"],
              let simulated = try? Date(value, strategy: .iso8601) else { return AppClock(offset: 0) }
        return AppClock(offset: simulated.timeIntervalSinceNow)
    }
}
