import Foundation

/// One line of Apple's daily subscription report: active subscriptions of one product, in one country, at one price.
/// Fields as documented: developer.apple.com/help/app-store-connect/reference/subscription-report
public struct SubscriptionRow: Codable, Hashable, Sendable {
    public var appID: String
    public var name: String
    /// 7 Days, 1 Month, 2 Months, 3 Months, 6 Months or 1 Year.
    public var duration: String
    /// Per subscription and period, in `currency`.
    public var proceeds: Double
    public var currency: String
    public var country: String
    public var active: Int
    public var trials: Int
    /// Introductory and promotional offers that are paid.
    public var offers: Int

    /// How many periods fit in a month, to turn the price per period into a monthly one.
    public var perMonth: Double {
        switch duration.lowercased() {
        case "7 days": 30.0 / 7
        case "2 months": 0.5
        case "3 months": 1.0 / 3
        case "6 months": 1.0 / 6
        case "1 year": 1.0 / 12
        default: 1
        }
    }
}

extension Client {
    /// Active subscriptions as of one day. Empty when the account sells none: Apple then answers that the vendor
    /// number is invalid for this report.
    public func subscriptionReport(vendor: String, day: String) async throws -> [SubscriptionRow] {
        do {
            let data = try await get("/v1/salesReports", query: [
                "filter[frequency]": "DAILY", "filter[reportType]": "SUBSCRIPTION", "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": vendor, "filter[reportDate]": day, "filter[version]": "1_4",
            ])
            return SubscriptionRow.parse(String(decoding: try Gzip.unzip(data), as: UTF8.self))
        } catch ASCError.http(let status, let body) where status == 404 || body.contains("Invalid vendor number") {
            if body.contains("not available yet") { throw SalesReportError.notYet }
            return []
        }
    }
}

extension SubscriptionRow {
    static func parse(_ text: String) -> [SubscriptionRow] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let app = column("App Apple ID"), name = column("Subscription Name"), duration = column("Standard Subscription Duration"),
            proceeds = column("Developer Proceeds"), currency = column("Proceeds Currency"), country = column("Country"),
            active = column("Active Standard Price Subscriptions"), trials = column("Active Free Trial Introductory Offer Subscriptions"),
            offers = ["Active Pay Up Front Introductory Offer Subscriptions", "Active Pay as You Go Introductory Offer Subscriptions",
                      "Pay Up Front Promotional Offer Subscriptions", "Pay As You Go Promotional Offer Subscriptions",
                      "Pay Up Front Offer Code Subscriptions", "Pay As You Go Offer Code Subscriptions"].compactMap(column)
        func value(_ fields: [String], _ index: Int?) -> String {
            guard let index, index < fields.count else { return "" }
            return fields[index].trimmingCharacters(in: .whitespaces)
        }
        return lines.dropFirst().compactMap { fields in
            guard fields.count > 5 else { return nil }
            return SubscriptionRow(appID: value(fields, app), name: value(fields, name), duration: value(fields, duration),
                                   proceeds: Double(value(fields, proceeds)) ?? 0, currency: value(fields, currency),
                                   country: value(fields, country), active: Int(value(fields, active)) ?? 0,
                                   trials: Int(value(fields, trials)) ?? 0,
                                   offers: offers.reduce(0) { $0 + (Int(value(fields, $1)) ?? 0) })
        }
    }
}
