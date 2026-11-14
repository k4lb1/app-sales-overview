import Foundation

/// One line of Apple's "App Store Discovery and Engagement Standard" report: how often an app was seen,
/// opened or tapped in the store on one day, by where it was found.
/// Fields as documented: developer.apple.com/documentation/analytics-reports/app-store-discovery-and-engagement
public struct DiscoveryRow: Codable, Hashable, Sendable {
    public var date: String
    public var appID: String
    /// Impression, Page view or Tap.
    public var event: String
    /// No page, Product page, Store sheet, …
    public var pageType: String
    /// App Store search, App Store browse, App referrer, Web referrer, …
    public var sourceType: String
    /// For taps: Get, Update, Redownload, Open, Share, …
    public var engagementType: String
    public var territory: String
    public var counts: Int
    public var uniqueCounts: Int
}

extension Client {
    public static let discoveryReport = "App Store Discovery and Engagement Standard"

    /// Asks Apple to produce the ongoing analytics reports for an app, unless it already does.
    /// Needs a key with the Admin role. Apple delivers the first data one to two days later.
    public func ensureAnalyticsRequest(appID: String) async throws -> String {
        let data = try await get("/v1/apps/\(appID)/analyticsReportRequests")
        let existing = try JSONDecoder().decode(Resources<RequestAttributes>.self, from: data).data
        if let ongoing = existing.first(where: { $0.attributes.accessType == "ONGOING" }) { return ongoing.id }
        let created = try await post("/v1/analyticsReportRequests", json: ["data": [
            "type": "analyticsReportRequests",
            "attributes": ["accessType": "ONGOING"],
            "relationships": ["app": ["data": ["type": "apps", "id": appID]]],
        ]])
        return try JSONDecoder().decode(Single.self, from: created).data.id
    }

    /// The daily instances of one report: (instance ID, processing day), newest first. Empty while Apple prepares the first ones.
    public func reportInstances(requestID: String, name: String) async throws -> [(id: String, day: String)] {
        let reports = try JSONDecoder().decode(Resources<ReportAttributes>.self, from: await get(
            "/v1/analyticsReportRequests/\(requestID)/reports", query: ["limit": "200"])).data
        guard let report = reports.first(where: { $0.attributes.name == name }) else { return [] }
        let instances = try JSONDecoder().decode(Resources<InstanceAttributes>.self, from: await get(
            "/v1/analyticsReports/\(report.id)/instances", query: ["filter[granularity]": "DAILY", "limit": "200"])).data
        return instances.map { ($0.id, $0.attributes.processingDate ?? "") }.sorted { $0.day > $1.day }
    }

    /// All lines of one instance. Its segments are files at signed URLs that need no token.
    public func discoveryRows(instanceID: String) async throws -> [DiscoveryRow] {
        let segments = try JSONDecoder().decode(Resources<SegmentAttributes>.self, from: await get(
            "/v1/analyticsReportInstances/\(instanceID)/segments")).data
        var rows: [DiscoveryRow] = []
        for segment in segments {
            guard let url = URL(string: segment.attributes.url) else { continue }
            let (data, _) = try await URLSession.shared.data(from: url)
            rows += DiscoveryRow.parse(String(decoding: try Gzip.unzip(data), as: UTF8.self))
        }
        return rows
    }
}

extension DiscoveryRow {
    /// Reads the report by its column names; the files are tab-separated (comma as a fallback).
    static func parse(_ text: String) -> [DiscoveryRow] {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let first = lines.first else { return [] }
        let separator: Character = first.contains("\t") ? "\t" : ","
        let header = first.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .init(charactersIn: "\" ")) }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let date = column("Date"), app = column("App Apple Identifier"), event = column("Event"), page = column("Page Type"),
            source = column("Source Type"), engagement = column("Engagement Type"), territory = column("Territory"),
            counts = column("Counts"), unique = column("Unique Counts")
        return lines.dropFirst().compactMap { line in
            let fields = line.split(separator: separator, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .init(charactersIn: "\" ")) }
            func value(_ index: Int?) -> String { index.flatMap { $0 < fields.count ? fields[$0] : nil } ?? "" }
            guard fields.count > 3 else { return nil }
            return DiscoveryRow(date: value(date), appID: value(app), event: value(event), pageType: value(page),
                                sourceType: value(source), engagementType: value(engagement), territory: value(territory),
                                counts: Int(value(counts)) ?? 0, uniqueCounts: Int(value(unique)) ?? 0)
        }
    }
}

private struct Resources<Attributes: Decodable>: Decodable {
    var data: [Item]
    struct Item: Decodable {
        var id: String
        var attributes: Attributes
    }
}

private struct Single: Decodable {
    var data: Item
    struct Item: Decodable { var id: String }
}

private struct RequestAttributes: Decodable { var accessType: String? }
private struct ReportAttributes: Decodable { var name: String }
private struct InstanceAttributes: Decodable { var processingDate: String? }
private struct SegmentAttributes: Decodable { var url: String }
