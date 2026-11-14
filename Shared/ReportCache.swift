import Foundation

/// The App Group that the app and its widgets share: the reports on disk and the apps.
enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? ""

    static var folder: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) ?? .applicationSupportDirectory
    }
}

/// Daily reports on disk, one file per day, in the App Group so the widgets read them too.
/// A day Apple has reported doesn't change any more, so it's fetched once; after that only new days are asked for.
enum ReportCache {
    private static var folder: URL {
        let url = AppGroup.folder.appending(path: "reports")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load(_ day: String) -> [SalesRow]? {
        guard let data = try? Data(contentsOf: folder.appending(path: "\(day).json")) else { return nil }
        return try? JSONDecoder().decode([SalesRow].self, from: data)
    }

    static func save(_ rows: [SalesRow], for day: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: folder.appending(path: "\(day).json"), options: .atomic)
    }

    /// The apps as last fetched, for the widgets when Apple can't be reached.
    static func loadApps() -> [StoreApp] {
        guard let data = try? Data(contentsOf: folder.appending(path: "apps.json")) else { return [] }
        return (try? JSONDecoder().decode([StoreApp].self, from: data)) ?? []
    }

    static func saveApps(_ apps: [StoreApp]) {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        try? data.write(to: folder.appending(path: "apps.json"), options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// The given days from disk, the missing ones from Apple, four at a time. Days Apple hasn't
    /// reported yet are left out.
    static func days(_ wanted: [String], client: Client, vendor: String) async throws -> [String: [SalesRow]] {
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
            for _ in 0..<4 { next() }
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
enum AnalyticsCache {
    private static var folder: URL {
        let url = AppGroup.folder.appending(path: "analytics")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load(_ instance: String) -> [DiscoveryRow]? {
        guard let data = try? Data(contentsOf: folder.appending(path: "\(instance).json")) else { return nil }
        return try? JSONDecoder().decode([DiscoveryRow].self, from: data)
    }

    static func save(_ rows: [DiscoveryRow], for instance: String) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: folder.appending(path: "\(instance).json"), options: .atomic)
    }

    /// The discovery lines of the last `days` days for these apps: asks Apple for the report where needed,
    /// and downloads only instances that are new or not settled yet.
    static func discovery(apps: [StoreApp], days: Int, client: Client) async throws -> [DiscoveryRow] {
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
