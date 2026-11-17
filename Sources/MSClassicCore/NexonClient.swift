import Foundation

/// Fetches Classic World maintenance notices from Nexon's public CMS feed.
public actor NexonClient {
    public static let defaultBaseURL = URL(string: "https://g.nexonstatic.com/maplestory/cms/v1/")!

    private let baseURL: URL
    private let session: URLSession
    /// Parsed notices keyed by post id, invalidated when the list entry's title/summary changes.
    private var cache: [Int: (key: String, notice: MaintenanceNotice?)] = [:]

    public init(baseURL: URL = NexonClient.defaultBaseURL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: config)
        }
    }

    public func fetchNewsList() async throws -> [NewsItem] {
        try await get([NewsItem].self, path: "news")
    }

    public func fetchDetail(id: Int) async throws -> NewsDetail {
        try await get(NewsDetail.self, path: "news/\(id)")
    }

    /// Classic maintenance notices posted within `lookback` of `now`. Posts already titled
    /// "[Completed]" are returned without fetching their body (their times no longer matter).
    public func fetchClassicMaintenance(now: Date = Date(), lookback: TimeInterval = 30 * 86_400)
        async throws -> [MaintenanceNotice]
    {
        let items = try await fetchNewsList()
            .filter { item in
                guard item.isClassicMaintenance else { return false }
                guard let posted = item.liveDateValue else { return false }
                return posted >= now.addingTimeInterval(-lookback)
            }
            .sorted { ($0.liveDateValue ?? .distantPast) > ($1.liveDateValue ?? .distantPast) }
            .prefix(Self.maxDetailFetches)

        var results: [MaintenanceNotice] = []
        try await withThrowingTaskGroup(of: (Int, String, MaintenanceNotice?).self) { group in
            for item in items {
                let key = "\(item.name)|\(item.summary ?? "")"
                if let cached = cache[item.id], cached.key == key {
                    if let n = cached.notice { results.append(n) }
                    continue
                }
                if NoticeParser.isCompleted(title: item.name, summary: item.summary) {
                    cache[item.id] = (key, nil)
                    continue
                }
                group.addTask { [self] in
                    let detail = try await self.fetchDetail(id: item.id)
                    return (item.id, key, NoticeParser.parse(detail))
                }
            }
            for try await (id, key, notice) in group {
                cache[id] = (key, notice)
                if let notice { results.append(notice) }
            }
        }
        return results.sorted { $0.start < $1.start }
    }

    /// The news list is ~160 KB and posts a few KB; refuse anything far larger.
    static let maxResponseBytes = 5_000_000
    /// At most this many not-yet-completed posts get their body fetched per refresh.
    static let maxDetailFetches = 10

    private func get<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MSClassicIsUp/1.0 (macOS menu bar app)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        // Only accept data served over HTTPS by the host we asked (no redirects elsewhere).
        guard http.url?.scheme == "https", http.url?.host == baseURL.host else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Unexpected redirect"])
        }
        guard http.expectedContentLength <= Self.maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }

        var data = Data()
        data.reserveCapacity(max(0, Int(http.expectedContentLength)))
        for try await byte in bytes {
            data.append(byte)
            if data.count > Self.maxResponseBytes { throw URLError(.dataLengthExceedsMaximum) }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
