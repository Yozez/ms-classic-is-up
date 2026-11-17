import Foundation
import Testing
@testable import MSClassicCore

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

func detailFixture(_ id: Int) throws -> NewsDetail {
    try JSONDecoder().decode(NewsDetail.self, from: fixture("news-\(id)"))
}

func utc(_ s: String) -> Date { try! Date(s, strategy: .iso8601) }

func makeDetail(_ body: String, name: String = "Test Maintenance", summary: String? = nil) -> NewsDetail {
    let json: [String: Any] = ["id": 1, "name": name, "summary": summary ?? "", "body": body]
    return try! JSONDecoder().decode(NewsDetail.self, from: JSONSerialization.data(withJSONObject: json))
}

@Suite struct NoticeParserTests {
    @Test func upcomingScheduledUpdate48557() throws {
        let n = try #require(NoticeParser.parse(detailFixture(48557)))
        #expect(n.start == utc("2026-11-18T13:00:00Z"))
        #expect(n.end == utc("2026-11-18T18:00:00Z"))
        #expect(!n.isCompleted)
        #expect(n.displayTitle == "Scheduled Game Update - November 18, 2026")
    }

    @Test func completedScheduledMaintenance47298() throws {
        let n = try #require(NoticeParser.parse(detailFixture(47298)))
        // 5:00 AM - 9:00 AM PDT (UTC -7)
        #expect(n.start == utc("2026-10-29T12:00:00Z"))
        #expect(n.end == utc("2026-10-29T16:00:00Z"))
        #expect(n.isCompleted)
        #expect(n.displayTitle == "Scheduled Maintenance - October 29, 2026")
    }

    @Test func completedUnscheduledWithUpdatedBanner47580() throws {
        let n = try #require(NoticeParser.parse(detailFixture(47580)))
        // 3:00 PM - 5:00 PM PST (UTC -8)
        #expect(n.start == utc("2026-11-04T23:00:00Z"))
        #expect(n.end == utc("2026-11-05T01:00:00Z"))
        #expect(n.isCompleted)
    }

    @Test func endOnNextDayRollsOver() throws {
        let body = "<p>Times:</p><p>Friday, January 1, 2027<br>PST (UTC -8): 10:00 PM - 2:00 AM January 2</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.start == utc("2027-01-02T06:00:00Z"))
        #expect(n.end == utc("2027-01-02T10:00:00Z"))
    }

    @Test func endWithoutDateBeforeStartRollsOver() throws {
        let body = "<p>Times:</p><p>Thursday, December 31, 2026<br>PST (UTC -8): 11:00 PM - 1:00 AM</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.start == utc("2027-01-01T07:00:00Z"))
        #expect(n.end == utc("2027-01-01T09:00:00Z"))
    }

    @Test func missingEndTimeIsOpenEnded() throws {
        let body = "<p><strong>Times:</strong></p><p>Wednesday, November 4, 2026<br>PST (UTC -8): 3:00 PM - TBD</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body, name: "Unscheduled Maintenance")))
        #expect(n.start == utc("2026-11-04T23:00:00Z"))
        #expect(n.end == nil)
    }

    @Test func proseFallbackWithDuration() throws {
        let body = "<p>We will be performing an unscheduled maintenance starting on Wednesday, November 4, 2026 at 3:00 PM PST (6:00 PM EST). We anticipate the maintenance to last approximately 2.5 hours.</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.start == utc("2026-11-04T23:00:00Z"))
        #expect(n.end == utc("2026-11-05T01:30:00Z"))
    }

    @Test func proseFallbackWithoutEnd() throws {
        let body = "<p>Maintenance starting on Wednesday, November 4, 2026 at 3:00 PM PST until further notice.</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.start == utc("2026-11-04T23:00:00Z"))
        #expect(n.end == nil)
    }

    @Test func extensionBannerMovesEnd() throws {
        let body = "<p><strong>[Updated 11/18 at 9:40 AM PST]</strong> The maintenance has been extended until 12:00 PM PST.</p>"
            + "<p>Times:</p><p>Wednesday, November 18, 2026<br>PST (UTC -8): 5:00 AM - 10:00 AM</p>"
        let n = try #require(NoticeParser.parse(makeDetail(body)))
        #expect(n.start == utc("2026-11-18T13:00:00Z"))
        #expect(n.end == utc("2026-11-18T20:00:00Z"))
    }

    @Test func nonMaintenancePostReturnsNil() {
        #expect(NoticeParser.parse(makeDetail("<p>Here you'll find a list of known issues.</p>")) == nil)
    }

    @Test func completedDetection() {
        #expect(NoticeParser.isCompleted(title: "[Completed] Scheduled Maintenance", summary: nil))
        #expect(NoticeParser.isCompleted(title: "Unscheduled Maintenance",
                                         summary: "The maintenance has been completed and we have extended..."))
        #expect(!NoticeParser.isCompleted(title: "Scheduled Game Update - November 18, 2026",
                                          summary: "MapleStory Classic World will be performing a scheduled maintenance"))
    }

    @Test func newsListFixtureDecodesAndFiltersClassicMaintenance() throws {
        let items = try JSONDecoder().decode([NewsItem].self, from: fixture("news-list"))
        #expect(items.count == 6)
        #expect(items.contains { $0.isMSCW == nil }) // some real posts omit the flag
        let classic = items.filter(\.isClassicMaintenance).map(\.id)
        #expect(classic.contains(48557))
        #expect(classic.contains(47580))
        #expect(classic.contains(47298))
        #expect(!classic.contains(48436)) // modern MapleStory known-issues post
    }
}
