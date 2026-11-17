import Foundation

/// An entry in Nexon's CMS news list (`/maplestory/cms/v1/news`).
public struct NewsItem: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let summary: String?
    public let category: String?
    public let isMSCW: Bool?
    public let liveDate: String?

    public init(id: Int, name: String, summary: String? = nil, category: String? = nil,
                isMSCW: Bool? = nil, liveDate: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.isMSCW = isMSCW
        self.liveDate = liveDate
    }

    public var liveDateValue: Date? { liveDate.flatMap(ISODate.parse) }

    /// True for MapleStory Classic World posts in the maintenance category.
    public var isClassicMaintenance: Bool {
        isMSCW == true && category?.lowercased() == "maintenance"
    }
}

/// A single news post (`/maplestory/cms/v1/news/{id}`).
public struct NewsDetail: Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let summary: String?
    public let body: String
    public let category: String?
    public let isMSCW: Bool?
    public let liveDate: String?
}

/// A parsed Classic World maintenance window.
public struct MaintenanceNotice: Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let start: Date
    /// `nil` when Nexon did not announce an end time ("until further notice").
    public let end: Date?
    public let isCompleted: Bool

    public init(id: Int, title: String, start: Date, end: Date?, isCompleted: Bool) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isCompleted = isCompleted
    }

    /// Title without bracketed status prefixes like "[Completed]" or "[Updated ...]".
    public var displayTitle: String {
        var t = title.trimmingCharacters(in: .whitespaces)
        while t.hasPrefix("["), let close = t.firstIndex(of: "]") {
            t = String(t[t.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        return t.isEmpty ? title : t
    }

    public var url: URL {
        URL(string: "https://www.nexon.com/maplestory/news/maintenance/\(id)")!
    }
}

public enum ServerState: String, Sendable, Equatable {
    /// No maintenance in progress according to official notices.
    case up
    /// An announced maintenance window is in progress.
    case maintenance
    /// The announced end time passed but Nexon hasn't marked the notice completed.
    case overrunning
    /// No data yet (network failure before the first successful fetch).
    case unknown
}

public struct StatusSnapshot: Sendable, Equatable {
    public let state: ServerState
    /// The maintenance in progress (or overrunning), if any.
    public let current: MaintenanceNotice?
    /// The next upcoming maintenance, if any.
    public let next: MaintenanceNotice?

    public init(state: ServerState, current: MaintenanceNotice? = nil, next: MaintenanceNotice? = nil) {
        self.state = state
        self.current = current
        self.next = next
    }

    public static let unknown = StatusSnapshot(state: .unknown)
}

enum ISODate {
    static func parse(_ string: String) -> Date? {
        if let d = try? Date(string, strategy: .iso8601) { return d }
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return try? fractional.parse(string)
    }
}
