import Foundation

/// Extracts maintenance windows from Nexon maintenance posts.
///
/// Posts contain a "Times:" block such as:
///
///     Wednesday, November 18, 2026
///     PST (UTC -8): 5:00 AM - 10:00 AM
///     EST (UTC -5): 8:00 AM - 1:00 PM
///     AEDT (UTC +11): 12:00 AM November 19 - 5:00 AM November 19
///
/// The first zone line (with its explicit UTC offset) is used. If that block is
/// missing, the prose sentence "starting on <date> at <time> <TZ>" plus
/// "last approximately N hours" is used instead.
public enum NoticeParser {

    /// Real maintenance posts are a few KB; anything far larger is not worth parsing.
    static let maxBodyBytes = 1_000_000
    /// Announced windows longer than this are treated as having no known end.
    static let maxWindow: TimeInterval = 72 * 3600

    public static func parse(_ detail: NewsDetail) -> MaintenanceNotice? {
        guard detail.body.utf8.count <= maxBodyBytes else { return nil }
        let text = plainText(fromHTML: detail.body)
        guard var window = timesBlockWindow(in: text) ?? proseWindow(in: text) else { return nil }
        if let extended = extendedEnd(in: text, after: window.start) {
            window.end = extended
        }
        if let end = window.end, end <= window.start || end.timeIntervalSince(window.start) > maxWindow {
            window.end = nil
        }
        return MaintenanceNotice(
            id: detail.id,
            title: detail.name,
            start: window.start,
            end: window.end,
            isCompleted: isCompleted(title: detail.name, summary: detail.summary)
        )
    }

    public static func isCompleted(title: String, summary: String?) -> Bool {
        if title.range(of: "[Completed]", options: .caseInsensitive) != nil { return true }
        if let summary,
           summary.range(of: #"^\s*(\[[^\]]*\]\s*)?The maintenance has been completed"#,
                         options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    // MARK: - HTML → text

    /// Flattens HTML into a single whitespace-normalized line.
    public static func plainText(fromHTML html: String) -> String {
        var s = html.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&nbsp;", " "), ("&#160;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&rsquo;", "’"), ("&ndash;", "–"),
            ("&mdash;", "—"),
        ]
        for (entity, value) in entities {
            s = s.replacingOccurrences(of: entity, with: value)
        }
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Strategies

    struct Window: Equatable {
        var start: Date
        var end: Date?
    }

    private static let time = #"\d{1,2}:\d{2}\s*[AaPp]\.?[Mm]\.?"#
    private static let monthDay = #"[A-Z][a-z]+\.? \d{1,2}"#
    private static let fullDate = #"[A-Z][a-z]+\.? \d{1,2}, \d{4}"#
    private static let dash = #"\s*[-–—]\s*"#

    static func timesBlockWindow(in text: String) -> Window? {
        let pattern =
            #"Times:\s*(?:[A-Z][a-z]+day,\s*)?(\#(fullDate))\s+[A-Z]{2,5}\s*\(\s*(?:UTC|GMT)\s*([+\-−]\s*\d{1,2}(?::\d{2})?)\s*\)\s*:\s*"#
            + #"(\#(time))(?:\s+(\#(monthDay)))?(?:\#(dash)(\#(time))(?:\s+(\#(monthDay)))?)?"#
        guard let g = firstMatch(pattern, in: text),
              let baseDate = g[1], let offsetText = g[2], let startTime = g[3],
              let base = DateParts(fullDate: baseDate),
              let offset = parseOffset(offsetText),
              let zone = safeTimeZone(offset: offset) else { return nil }

        let startDay = g[4].flatMap { base.with(monthDay: $0) } ?? base
        guard let start = startDay.date(time: startTime, zone: zone) else { return nil }

        var end: Date?
        if let endTime = g[5] {
            if let endMonthDay = g[6], let endDay = base.with(monthDay: endMonthDay) {
                end = endDay.date(time: endTime, zone: zone)
            } else {
                end = startDay.date(time: endTime, zone: zone)
                if let e = end, e <= start { end = e.addingTimeInterval(86_400) }
            }
        }
        return Window(start: start, end: end)
    }

    static func proseWindow(in text: String) -> Window? {
        let pattern = #"starting (?:on )?(?:[A-Z][a-z]+day,\s*)?(\#(fullDate)),? at (\#(time))\s*\(?([A-Z]{2,4})\b"#
        guard let g = firstMatch(pattern, in: text),
              let dateText = g[1], let timeText = g[2], let tz = g[3],
              let day = DateParts(fullDate: dateText),
              let offset = abbreviationOffsets[tz],
              let zone = safeTimeZone(offset: offset),
              let start = day.date(time: timeText, zone: zone) else { return nil }

        var end: Date?
        if let h = firstMatch(#"last (?:approximately |about |around )?(\d+(?:\.\d+)?) hours?"#, in: text),
           let hoursText = h[1], let hours = Double(hoursText) {
            if hours > 0, hours * 3600 <= maxWindow {
                end = start.addingTimeInterval(hours * 3600)
            }
        } else if let c = firstMatch(#"conclud\w* (?:around |at )?(\#(time))\s*\(?([A-Z]{2,4})\b"#, in: text),
                  let endTime = c[1], let endTZ = c[2], let endOffset = abbreviationOffsets[endTZ],
                  let endZone = safeTimeZone(offset: endOffset),
                  var e = day.date(time: endTime, zone: endZone) {
            if e <= start { e = e.addingTimeInterval(86_400) }
            end = e
        }
        return Window(start: start, end: end)
    }

    /// Handles update banners such as "[Updated ...] The maintenance has been extended until 12:00 PM PST".
    static func extendedEnd(in text: String, after start: Date) -> Date? {
        let pattern = #"extended (?:until|to|through) (?:approximately |around )?(\#(time))\s*\(?([A-Z]{2,4})\b"#
        guard let g = firstMatch(pattern, in: text),
              let timeText = g[1], let tz = g[2], let offset = abbreviationOffsets[tz],
              let zone = safeTimeZone(offset: offset) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let comps = cal.dateComponents([.year, .month, .day], from: start)
        guard let year = comps.year, let month = comps.month, let day = comps.day,
              var end = DateParts(year: year, month: month, day: day).date(time: timeText, zone: zone)
        else { return nil }
        while end <= start { end = end.addingTimeInterval(86_400) }
        return end
    }

    // MARK: - Helpers

    static let abbreviationOffsets: [String: Int] = [
        "PST": -8 * 3600, "PDT": -7 * 3600, "PT": -8 * 3600,
        "EST": -5 * 3600, "EDT": -4 * 3600,
        "UTC": 0, "GMT": 0,
        "CET": 1 * 3600, "CEST": 2 * 3600,
    ]

    /// Real-world UTC offsets range from -12:00 to +14:00; anything else is rejected.
    static func safeTimeZone(offset: Int) -> TimeZone? {
        guard abs(offset) <= 14 * 3600 else { return nil }
        return TimeZone(secondsFromGMT: offset)
    }

    static func parseOffset(_ text: String) -> Int? {
        let cleaned = text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: " ", with: "")
        guard let sign = cleaned.first, sign == "+" || sign == "-" else { return nil }
        let parts = cleaned.dropFirst().split(separator: ":")
        guard let hours = Int(parts.first ?? "") else { return nil }
        let minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let total = hours * 3600 + minutes * 60
        return sign == "-" ? -total : total
    }

    /// Returns capture groups of the first match (index 0 is the whole match).
    static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) }
        }
    }
}

/// A calendar day, independent of time zone.
struct DateParts: Equatable {
    let year: Int
    let month: Int
    let day: Int

    private static let months: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// "November 18, 2026"
    init?(fullDate: String) {
        let parts = fullDate.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: ".", with: "")
            .split(separator: " ")
        guard parts.count == 3,
              let month = DateParts.month(String(parts[0])),
              let day = Int(parts[1]), let year = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Same year (or the next one when the month wraps), from "November 19".
    func with(monthDay: String) -> DateParts? {
        let parts = monthDay.replacingOccurrences(of: ".", with: "").split(separator: " ")
        guard parts.count == 2, let m = DateParts.month(String(parts[0])), let d = Int(parts[1]) else { return nil }
        return DateParts(year: m < month ? year + 1 : year, month: m, day: d)
    }

    /// Combines the day with "5:00 AM" in the given zone.
    func date(time: String, zone: TimeZone) -> Date? {
        let t = time.uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: "")
        guard t.count >= 6 else { return nil }
        let isPM = t.hasSuffix("PM")
        let hm = t.dropLast(2).split(separator: ":")
        guard hm.count == 2, var hour = Int(hm[0]), let minute = Int(hm[1]),
              (1...12).contains(hour), (0..<60).contains(minute) else { return nil }
        if hour == 12 { hour = 0 }
        if isPM { hour += 12 }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
    }

    private static func month(_ name: String) -> Int? {
        months[String(name.lowercased().prefix(3))]
    }
}
