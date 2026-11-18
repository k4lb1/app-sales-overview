import Foundation
import Testing
@testable import ASCKit

/// Parsing of Apple's subscription event report, based on the documented columns.
struct SubscriptionTests {
    static let header = ["Event Date", "Event", "App Name", "App Apple ID", "Subscription Name", "Subscription Apple ID",
                         "Subscription Group ID", "Standard Subscription Duration", "Subscription Offer Type",
                         "Subscription Offer Duration", "Marketing Opt-In", "Marketing Opt-In Duration", "Preserved Pricing",
                         "Proceeds Reason", "Subscription Offer Name", "Promotional Offer ID", "Consecutive Paid Periods",
                         "Original Start Date", "Device", "Client", "State", "Country", "Previous Subscription Name",
                         "Previous Subscription Apple ID", "Days Before Canceling", "Cancellation Reason", "Days Canceled",
                         "Quantity"].joined(separator: "\t")

    static func line(_ event: String, offer: String = "", reason: String = "", quantity: Int) -> String {
        ["2026-11-14", event, "Moss", "123", "Moss Plus", "456", "789", "1 Month", offer, "", "", "", "", "", "", "", "", "",
         "iPhone", "", "", "US", "", "", "", reason, "", "\(quantity)"].joined(separator: "\t")
    }

    @Test func eventsParseAndSortIntoKinds() {
        let text = [Self.header,
                    Self.line("Start Introductory Offer", offer: "Free Trial", quantity: 5),
                    Self.line("Paid Subscription from Introductory Offer", quantity: 3),
                    Self.line("Cancel", offer: "Free Trial", reason: "Canceled", quantity: 1),
                    Self.line("Canceled from Billing Retry", reason: "Billing issue", quantity: 2),
                    Self.line("Reactivate with Upgrade", quantity: 1),
                    Self.line("Renewal from Billing Retry", quantity: 1)].joined(separator: "\n")
        let events = SubscriptionEvent.parse(text)
        #expect(events.map(\.kind) == [.start, .conversion, .cancellation, .cancellation, .reactivation, .other])
        #expect(events.map(\.quantity) == [5, 3, 1, 2, 1, 1])
        #expect(events[2].inTrial && !events[3].inTrial)
        #expect(events[3].cancellationReason == "Billing issue")
    }

    @Test func churnAndTrialConversion() {
        let app = StoreApp(id: "123", name: "Moss", bundleID: "", sku: "", versions: [])
        func row(_ active: Int) -> SubscriptionRow {
            SubscriptionRow(appID: "123", name: "Moss Plus", duration: "1 Month", proceeds: 2, currency: "EUR", country: "DE",
                            active: active, trials: 0, offers: 0)
        }
        func cancel(_ day: String, trial: Bool, _ count: Int) -> SubscriptionEvent {
            SubscriptionEvent(date: day, event: "Cancel", appID: "123", name: "Moss Plus", offerType: trial ? "Free Trial" : "", quantity: count)
        }
        let figures = Figures(apps: [app], subscriptionDays: [
            "2026-11-13": SubscriptionDay(rows: [row(100)], events: [cancel("2026-11-13", trial: false, 2)]),
            "2026-11-14": SubscriptionDay(rows: [row(98)], events: [
                cancel("2026-11-14", trial: false, 3), cancel("2026-11-14", trial: true, 1),
                SubscriptionEvent(date: "2026-11-14", event: "Paid Subscription from Introductory Offer", appID: "123", name: "Moss Plus", quantity: 3),
            ]),
        ])
        #expect(figures.churn(days: 2, app: app) == 0.05)
        #expect(figures.trialConversion(days: 2, app: app) == 0.75)
        #expect(figures.subscriptionTrend(days: 2, app: app).map(\.subscribers) == [100, 98])
        #expect(figures.cancellationReasons(days: 2).first?.count == 6)
    }
}
