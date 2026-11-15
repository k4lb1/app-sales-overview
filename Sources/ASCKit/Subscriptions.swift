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

/// One line of Apple's subscription event report: how many subscribers did the same thing on one day.
public struct SubscriptionEvent: Codable, Hashable, Sendable {
    public var date: String
    /// Apple's name for it, e.g. "Subscribe", "Cancel", "Paid Subscription from Introductory Offer". There are
    /// about two hundred; `kind` sorts them into the few that count.
    public var event: String
    public var appID: String
    public var name: String
    /// "Free Trial", "Pay As You Go", "Pay Up Front" or empty for the standard price.
    public var offerType: String
    public var country: String
    /// "Billing issue", "Price increase", "Canceled", "Removed from Sale" or "Other", for cancellations.
    public var cancellationReason: String
    public var quantity: Int

    public init(date: String, event: String, appID: String, name: String, offerType: String = "", country: String = "",
                cancellationReason: String = "", quantity: Int) {
        self.date = date
        self.event = event
        self.appID = appID
        self.name = name
        self.offerType = offerType
        self.country = country
        self.cancellationReason = cancellationReason
        self.quantity = quantity
    }

    public enum Kind: Sendable {
        /// A new subscriber at a price, or one starting an introductory offer or offer code.
        case start
        /// An introductory offer (usually the free trial) turned into a paid subscription.
        case conversion
        case cancellation
        case reactivation
        case refund
        case billingRetry
        case other
    }

    public var kind: Kind {
        let event = event.lowercased()
        if event.hasPrefix("cancel") { return .cancellation }
        if event == "subscribe" || event.hasPrefix("start ") { return .start }
        if event.hasPrefix("reactivat") { return .reactivation }
        if event.hasPrefix("refund") { return .refund }
        if event.hasPrefix("billing retry") { return .billingRetry }
        if event.hasSuffix("from introductory offer") || event.hasSuffix("from introductory price") { return .conversion }
        return .other
    }

    /// Whether it happened during a free trial: a cancellation then means the trial won't convert.
    public var inTrial: Bool { offerType.lowercased().contains("free trial") }
}

extension Client {
    /// What subscribers did on one day: started, converted, cancelled, came back. Empty when the account sells no
    /// subscriptions.
    public func subscriptionEvents(vendor: String, day: String, version: String = "1_4") async throws -> [SubscriptionEvent] {
        do {
            let data = try await get("/v1/salesReports", query: [
                "filter[frequency]": "DAILY", "filter[reportType]": "SUBSCRIPTION_EVENT", "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": vendor, "filter[reportDate]": day, "filter[version]": version,
            ])
            return SubscriptionEvent.parse(String(decoding: try Gzip.unzip(data), as: UTF8.self))
        } catch ASCError.http(400, let body) where version == "1_4" && body.lowercased().contains("version") {
            // Apple's documentation names 1_3 for this report; 1_4 is what the summary report has.
            return try await subscriptionEvents(vendor: vendor, day: day, version: "1_3")
        } catch ASCError.http(let status, let body) where status == 404 || body.contains("Invalid vendor number") {
            if body.contains("not available yet") { throw SalesReportError.notYet }
            return []
        }
    }

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

extension SubscriptionEvent {
    static func parse(_ text: String) -> [SubscriptionEvent] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let date = column("Event Date"), event = column("Event"), app = column("App Apple ID"), name = column("Subscription Name"),
            offer = column("Subscription Offer Type"), country = column("Country"), reason = column("Cancellation Reason"),
            quantity = column("Quantity")
        func value(_ fields: [String], _ index: Int?) -> String {
            guard let index, index < fields.count else { return "" }
            return fields[index].trimmingCharacters(in: .whitespaces)
        }
        return lines.dropFirst().compactMap { fields in
            guard fields.count > 5, !value(fields, event).isEmpty else { return nil }
            return SubscriptionEvent(date: value(fields, date), event: value(fields, event), appID: value(fields, app),
                                     name: value(fields, name), offerType: value(fields, offer), country: value(fields, country),
                                     cancellationReason: value(fields, reason), quantity: Int(value(fields, quantity)) ?? 1)
        }
    }
}
