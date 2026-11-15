import Foundation

/// The App Group that the app and its widgets share: the reports on disk and the apps.
public enum AppGroup {
    public static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""

    public static var folder: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) ?? .applicationSupportDirectory
    }
}

/// Daily reports on disk, one file per day, in the App Group so the widgets read them too.
/// A day Apple has reported doesn't change any more, so it's fetched once; after that only new days are asked for.
public enum ReportCache {
    private static var folder: URL {
        let url = AppGroup.folder.appending(path: "reports")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A day saved before the app read the version column is fetched again, for the release marks in the charts.
    public static func load(_ day: String) -> [SalesRow]? {
        guard let data = try? Data(contentsOf: folder.appending(path: "\(day).json")),
              let rows = try? JSONDecoder().decode([SalesRow].self, from: data),
              rows.isEmpty || rows.contains(where: { $0.version != nil }) else { return nil }
        return rows
    }

    public static func save(_ rows: [SalesRow], for day: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: folder.appending(path: "\(day).json"), options: .atomic)
    }

    /// The apps as last fetched, for the widgets when Apple can't be reached.
    public static func loadApps() -> [StoreApp] {
        guard let data = try? Data(contentsOf: folder.appending(path: "apps.json")) else { return [] }
        return (try? JSONDecoder().decode([StoreApp].self, from: data)) ?? []
    }

    public static func saveApps(_ apps: [StoreApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: folder.appending(path: "apps.json"), options: .atomic)
    }

    /// When the key changes, the old account's reports go.
    public static func clear() {
        for kind in ["reports", "analytics", "months", "payouts"] {
            try? FileManager.default.removeItem(at: AppGroup.folder.appending(path: kind))
        }
    }

    /// The given days from disk, the missing ones from Apple, six at a time. Days Apple hasn't
    /// reported yet are left out.
    public static func days(_ wanted: [String], client: Client, vendor: String) async throws -> [String: [SalesRow]] {
        var result: [String: [SalesRow]] = [:]
        var missing: [String] = []
        for day in wanted {
            if let rows = load(day) { result[day] = rows } else { missing.append(day) }
        }
        try await withThrowingTaskGroup(of: (String, [SalesRow]?).self) { group in
            var queue = missing[...]
            func next() {
                guard let day = queue.popFirst() else { return }
                group.addTask {
                    do { return (day, try await client.salesReport(vendor: vendor, day: day)) }
                    catch SalesReportError.notYet { return (day, nil) }
                }
            }
            for _ in 0..<6 { next() }
            for try await (day, rows) in group {
                if let rows {
                    result[day] = rows
                    save(rows, for: day)
                }
                next()
            }
        }
        return result
    }
}

/// The analytics report instances on disk, one file per instance. Apple completes a day within three days,
/// so younger instances are fetched again until they're settled.
public enum AnalyticsCache {
    private static var folder: URL {
        let url = AppGroup.folder.appending(path: "analytics")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func load(_ instance: String) -> [DiscoveryRow]? {
        guard let data = try? Data(contentsOf: folder.appending(path: "\(instance).json")) else { return nil }
        return try? JSONDecoder().decode([DiscoveryRow].self, from: data)
    }

    public static func save(_ rows: [DiscoveryRow], for instance: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: folder.appending(path: "\(instance).json"), options: .atomic)
    }

    /// The discovery lines of the last `days` days for these apps: asks Apple for the report where needed,
    /// and downloads only instances that are new or not settled yet.
    public static func discovery(apps: [StoreApp], days: Int, client: Client) async throws -> [DiscoveryRow] {
        let settled = ReportDay.string(.now.addingTimeInterval(-4 * 86_400))
        let oldest = ReportDay.string(.now.addingTimeInterval(-Double(days + 4) * 86_400))
        var rows: [DiscoveryRow] = []
        for app in apps {
            let request = try await client.ensureAnalyticsRequest(appID: app.id)
            for instance in try await client.reportInstances(requestID: request, name: Client.discoveryReport) where instance.day >= oldest {
                if instance.day < settled, let cached = load(instance.id) {
                    rows += cached
                } else {
                    let fresh = try await client.discoveryRows(instanceID: instance.id)
                    save(fresh, for: instance.id)
                    rows += fresh
                }
            }
        }
        return rows
    }
}

/// Monthly sales and financial reports on disk, one file per month. A month that's reported doesn't change.
public enum MonthCache {
    private static func folder(_ kind: String) -> URL {
        let url = AppGroup.folder.appending(path: kind)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func load<Row: Decodable>(_ kind: String, _ month: String) -> [Row]? {
        guard let data = try? Data(contentsOf: folder(kind).appending(path: "\(month).json")) else { return nil }
        return try? JSONDecoder().decode([Row].self, from: data)
    }

    public static func save<Row: Encodable>(_ rows: [Row], _ kind: String, _ month: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: folder(kind).appending(path: "\(month).json"), options: .atomic)
    }

    /// The months from disk, the rest from Apple. A financial month can come out empty before Apple has published it,
    /// so an empty month is only kept once it's two months past.
    public static func months<Row: Codable & Sendable>(_ kind: String, _ wanted: [String],
                                                fetch: @escaping @Sendable (String) async throws -> [Row]) async -> [String: [Row]] {
        let settled = ReportDay.recentMonths(2).last ?? ""
        var result: [String: [Row]] = [:]
        for month in wanted {
            if let rows: [Row] = load(kind, month) {
                result[month] = rows
            } else if let rows = try? await fetch(month) {
                result[month] = rows
                if !rows.isEmpty || month < settled { save(rows, kind, month) }
            }
        }
        return result
    }
}
