import Foundation

/// One line of Apple's daily sales summary: one product, in one country, on one device, at one price.
public struct SalesRow: Codable, Hashable, Sendable {
    public var title: String
    public var sku: String
    /// The app's Apple ID, or the in-app purchase's.
    public var appleID: String
    /// For in-app purchases and subscriptions: the SKU of the app they belong to.
    public var parentSKU: String
    public var productType: String
    public var units: Int
    /// What the developer gets per unit, in `proceedsCurrency`.
    public var proceeds: Double
    public var proceedsCurrency: String
    public var country: String
    public var device: String

    public var kind: SalesKind { SalesKind(productType) }
    /// The app this line counts for: the app itself, or the parent of an in-app purchase.
    public var appSKU: String { parentSKU.isEmpty ? sku : parentSKU }
    /// Apple reports refunds as lines with negative units.
    public var isRefund: Bool { units < 0 }
}

/// What a line stands for, from Apple's product type identifier.
public enum SalesKind: String, Codable, Sendable {
    case download, update, redownload, purchase, other

    init(_ type: String) {
        switch type {
        case "1", "1F", "1T", "F1", "1E", "1EP", "1EU": self = .download
        case "7", "7F", "7T", "F7": self = .update
        case "3", "3F", "3T", "F3": self = .redownload
        case let t where t.hasPrefix("IA") || t.hasPrefix("FI"): self = .purchase
        default: self = .other
        }
    }
}

public enum SalesReportError: Error {
    /// Apple hasn't made this day's report yet (daily reports come in the morning, Pacific time).
    case notYet
}

extension Client {
    /// The daily sales summary for one day (Pacific time, as Apple counts days). Empty when there were no sales.
    public func salesReport(vendor: String, day: String) async throws -> [SalesRow] {
        try await salesReport(vendor: vendor, frequency: "DAILY", date: day)
    }

    /// The monthly sales summary for one month ("yyyy-MM").
    public func salesReport(vendor: String, month: String) async throws -> [SalesRow] {
        try await salesReport(vendor: vendor, frequency: "MONTHLY", date: month)
    }

    private func salesReport(vendor: String, frequency: String, date: String) async throws -> [SalesRow] {
        do {
            let data = try await get("/v1/salesReports", query: [
                "filter[frequency]": frequency, "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
                // Apple versions the reports separately; the monthly summary is still at 1_0.
                "filter[vendorNumber]": vendor, "filter[reportDate]": date, "filter[version]": frequency == "MONTHLY" ? "1_0" : "1_1",
            ])
            return SalesRow.parse(String(decoding: try Gzip.unzip(data), as: UTF8.self))
        } catch ASCError.http(404, let body) {
            if body.contains("no sales") { return [] }
            if body.contains("not available yet") { throw SalesReportError.notYet }
            throw ASCError.http(404, body)
        }
    }
}

extension SalesRow {
    /// Reads Apple's tab-separated report by its column names, so new or moved columns don't break it.
    static func parse(_ text: String) -> [SalesRow] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let title = column("Title"), sku = column("SKU"), appleID = column("Apple Identifier"),
            parent = column("Parent Identifier"), type = column("Product Type Identifier"), units = column("Units"),
            proceeds = column("Developer Proceeds"), currency = column("Currency of Proceeds"),
            country = column("Country Code"), device = column("Device")
        func value(_ fields: [String], _ index: Int?) -> String {
            guard let index, index < fields.count else { return "" }
            return fields[index].trimmingCharacters(in: .whitespaces)
        }
        return lines.dropFirst().compactMap { fields in
            guard fields.count > 5 else { return nil }
            return SalesRow(title: value(fields, title), sku: value(fields, sku), appleID: value(fields, appleID),
                            parentSKU: value(fields, parent), productType: value(fields, type),
                            units: Int(value(fields, units)) ?? 0, proceeds: Double(value(fields, proceeds)) ?? 0,
                            proceedsCurrency: value(fields, currency), country: value(fields, country),
                            device: value(fields, device))
        }
    }
}

/// Apple counts report days in Pacific time.
public enum ReportDay {
    public static let timeZone = TimeZone(identifier: "America/Los_Angeles")!

    public static func string(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func date(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    /// The `count` months before this one, newest first, as "yyyy-MM".
    public static func recentMonths(_ count: Int, from now: Date = .now) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return (1...max(1, count)).compactMap { calendar.date(byAdding: .month, value: -$0, to: now) }
            .map { String(string($0).prefix(7)) }
    }

    /// The `count` days before today (Pacific), newest first: yesterday, the day before, …
    public static func recent(_ count: Int, from now: Date = .now) -> [String] {
        (1...max(1, count)).map { string(now.addingTimeInterval(-86_400 * Double($0))) }
    }
}
