import Foundation

/// Subscriptions over time, from the daily subscription reports: how many, what they bring in a month, who started,
/// converted or cancelled. Needs `subscriptionDays`, which only the Mac loads.
extension Figures {
    public struct SubscriptionPoint: Sendable {
        public let day: Date
        /// Paying subscribers, at the standard price or a paid offer.
        public let subscribers: Int
        public let trials: Int
        /// Monthly recurring revenue in the display currency.
        public let monthly: Double
    }

    /// The newest `count` days Apple reported subscriptions for, newest first.
    public func subscriptionReportDays(_ count: Int, previous: Bool = false) -> [String] {
        Array(subscriptionDays.keys.sorted(by: >).dropFirst(previous ? count : 0).prefix(count))
    }

    /// One point per reported day, oldest first.
    public func subscriptionTrend(days count: Int, app: StoreApp? = nil) -> [SubscriptionPoint] {
        subscriptionReportDays(count).reversed().compactMap { day in
            guard let rows = subscriptionDays[day]?.rows, let date = ReportDay.date(day) else { return nil }
            let own = rows.filter { app == nil || $0.appID == app!.id }
            return SubscriptionPoint(day: date, subscribers: own.reduce(0) { $0 + $1.active + $1.offers },
                                     trials: own.reduce(0) { $0 + $1.trials }, monthly: monthlyRecurring(rows, app: app))
        }
    }

    /// The events of a kind over the newest `count` days (or the days before them), counted per subscriber.
    /// `inTrial` narrows to events during a free trial (true) or outside one (false).
    public func subscriptionEvents(_ kind: SubscriptionEvent.Kind, days count: Int, app: StoreApp? = nil, previous: Bool = false,
                                   inTrial: Bool? = nil) -> Int {
        events(days: count, app: app, previous: previous)
            .filter { $0.kind == kind && (inTrial == nil || $0.inTrial == inTrial!) }
            .reduce(0) { $0 + $1.quantity }
    }

    /// The share of paying subscribers at the start of the period who cancelled during it; nil before there's a
    /// full period or anyone paying.
    public func churn(days count: Int, app: StoreApp? = nil) -> Double? {
        let trend = subscriptionTrend(days: count, app: app)
        guard trend.count == count, let first = trend.first, first.subscribers > 0 else { return nil }
        return Double(subscriptionEvents(.cancellation, days: count, app: app, inTrial: false)) / Double(first.subscribers)
    }

    /// Of the trials that ended in the period, the share that turned into paying ones; nil while none ended.
    public func trialConversion(days count: Int, app: StoreApp? = nil) -> Double? {
        let converted = subscriptionEvents(.conversion, days: count, app: app)
        let lost = subscriptionEvents(.cancellation, days: count, app: app, inTrial: true)
        guard converted + lost > 0 else { return nil }
        return Double(converted) / Double(converted + lost)
    }

    /// Why subscribers cancelled in the period, most common first.
    public func cancellationReasons(days count: Int, app: StoreApp? = nil) -> [(reason: String, count: Int)] {
        events(days: count, app: app).filter { $0.kind == .cancellation }
            .reduce(into: [String: Int]()) { $0[$1.cancellationReason.isEmpty ? "Other" : $1.cancellationReason, default: 0] += $1.quantity }
            .map { ($0.key, $0.value) }.sorted { $0.count > $1.count }
    }

    private func events(days count: Int, app: StoreApp?, previous: Bool = false) -> [SubscriptionEvent] {
        subscriptionReportDays(count, previous: previous).flatMap { subscriptionDays[$0]?.events ?? [] }
            .filter { app == nil || $0.appID == app!.id }
    }
}
