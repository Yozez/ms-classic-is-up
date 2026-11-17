import Foundation
import Testing
@testable import MSClassicCore

@Suite struct StatusEvaluatorTests {
    let nov18 = MaintenanceNotice(id: 48557, title: "Scheduled Game Update - November 18, 2026",
                                  start: utc("2026-11-18T13:00:00Z"), end: utc("2026-11-18T18:00:00Z"),
                                  isCompleted: false)
    let oct29Done = MaintenanceNotice(id: 47298, title: "[Completed] Scheduled Maintenance - October 29, 2026",
                                      start: utc("2026-10-29T12:00:00Z"), end: utc("2026-10-29T16:00:00Z"),
                                      isCompleted: true)

    @Test func noNoticesIsUp() {
        let s = StatusEvaluator.evaluate([], now: utc("2026-11-17T12:00:00Z"))
        #expect(s == StatusSnapshot(state: .up))
    }

    @Test func upcomingIsUpWithNext() {
        let s = StatusEvaluator.evaluate([oct29Done, nov18], now: utc("2026-11-17T17:00:00Z"))
        #expect(s.state == .up)
        #expect(s.next == nov18)
        #expect(s.current == nil)
    }

    @Test func duringWindowIsMaintenance() {
        let s = StatusEvaluator.evaluate([nov18], now: utc("2026-11-18T14:00:00Z"))
        #expect(s.state == .maintenance)
        #expect(s.current == nov18)
        #expect(s.next == nil)
    }

    @Test func atExactStartIsMaintenance() {
        #expect(StatusEvaluator.evaluate([nov18], now: nov18.start).state == .maintenance)
    }

    @Test func pastEndNotCompletedIsOverrunning() {
        let s = StatusEvaluator.evaluate([nov18], now: utc("2026-11-18T19:00:00Z"))
        #expect(s.state == .overrunning)
        #expect(s.current == nov18)
    }

    @Test func longPastEndIsUp() {
        let s = StatusEvaluator.evaluate([nov18], now: utc("2026-11-19T01:00:00Z"))
        #expect(s.state == .up)
    }

    @Test func completedDuringWindowIsUp() {
        let done = MaintenanceNotice(id: nov18.id, title: "[Completed] " + nov18.title,
                                     start: nov18.start, end: nov18.end, isCompleted: true)
        #expect(StatusEvaluator.evaluate([done], now: utc("2026-11-18T14:00:00Z")).state == .up)
    }

    @Test func openEndedIsMaintenanceThenExpires() {
        let open = MaintenanceNotice(id: 2, title: "Unscheduled Maintenance",
                                     start: utc("2026-11-04T23:00:00Z"), end: nil, isCompleted: false)
        #expect(StatusEvaluator.evaluate([open], now: utc("2026-11-05T05:00:00Z")).state == .maintenance)
        #expect(StatusEvaluator.evaluate([open], now: utc("2026-11-06T05:00:00Z")).state == .up)
    }

    @Test func nextIsEarliestUpcoming() {
        let later = MaintenanceNotice(id: 3, title: "Later", start: utc("2026-12-02T13:00:00Z"),
                                      end: utc("2026-12-02T17:00:00Z"), isCompleted: false)
        let s = StatusEvaluator.evaluate([later, nov18], now: utc("2026-11-17T00:00:00Z"))
        #expect(s.next == nov18)
    }

    @Test func endToEndFromFixtures() throws {
        let notices = try [48557, 47298, 47580].compactMap { NoticeParser.parse(try detailFixture($0)) }
        #expect(notices.count == 3)
        let before = StatusEvaluator.evaluate(notices, now: utc("2026-11-17T17:00:00Z"))
        #expect(before.state == .up)
        #expect(before.next?.id == 48557)
        let during = StatusEvaluator.evaluate(notices, now: utc("2026-11-18T15:30:00Z"))
        #expect(during.state == .maintenance)
        #expect(during.current?.id == 48557)
    }
}
