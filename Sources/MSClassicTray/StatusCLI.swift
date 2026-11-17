import Foundation
import MSClassicCore

/// Headless mode: `MSClassicTray --status` prints the current status and exits.
/// Exit code: 0 = up, 1 = maintenance/overrunning, 2 = error.
enum StatusCLI {
    static func run() -> Int32 {
        let clock = AppClock.fromEnvironment()
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<[MaintenanceNotice], Error> = .success([])
        Task.detached {
            do {
                result = .success(try await NexonClient().fetchClassicMaintenance(now: clock.now))
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()

        switch result {
        case .failure(let error):
            print("error: \(error.localizedDescription)")
            return 2
        case .success(let notices):
            let now = clock.now
            let snapshot = StatusEvaluator.evaluate(notices, now: now)
            let fmt = Date.FormatStyle(date: .abbreviated, time: .shortened)
            print("now:     \(now.formatted(fmt)) (\(TimeZone.current.identifier))")
            print("state:   \(snapshot.state.rawValue)")
            if let c = snapshot.current {
                print("current: \(c.displayTitle) — ends \(c.end?.formatted(fmt) ?? "until further notice")")
            }
            if let n = snapshot.next {
                print("next:    \(n.displayTitle)")
                print("         \(n.start.formatted(fmt)) → \(n.end?.formatted(fmt) ?? "?")")
            } else {
                print("next:    none scheduled")
            }
            print("notices: \(notices.map { "#\($0.id)" }.joined(separator: ", "))")
            return snapshot.state == .up ? 0 : 1
        }
    }
}
