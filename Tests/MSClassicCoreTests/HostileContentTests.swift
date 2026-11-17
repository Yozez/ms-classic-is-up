import Foundation
import Testing
@testable import MSClassicCore

/// Content from the network must never crash the app or produce absurd windows.
@Suite struct HostileContentTests {
    @Test func outOfRangeUTCOffsetIsRejectedNotCrash() {
        let body = "<p>Times:</p><p>Wednesday, November 18, 2026<br>PST (UTC +99): 5:00 AM - 10:00 AM</p>"
        #expect(NoticeParser.parse(makeDetail(body)) == nil)
    }

    @Test func absurdDurationIsIgnored() throws {
        let body = "<p>Maintenance starting on Wednesday, November 4, 2026 at 3:00 PM PST. "
            + "We anticipate the maintenance to last approximately 99999999999999999999 hours.</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.end == nil)
    }

    @Test func overlongBodyIsIgnoredCheaply() {
        let body = String(repeating: "Times: aaaaaaaaaa ", count: 200_000)
        #expect(NoticeParser.parse(makeDetail(body)) == nil)
    }

    @Test func countdownNeverTraps() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: .infinity), from: now) == "999d+")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: 1e300), from: now) == "999d+")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: .nan), from: now) == "0m")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: -5), from: now) == "0m")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: 2 * 3600 + 14 * 60), from: now) == "2h 14m")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: 26 * 3600), from: now) == "1d 2h")
        #expect(Countdown.format(to: Date(timeIntervalSinceReferenceDate: 59), from: now) == "1m")
    }
}
