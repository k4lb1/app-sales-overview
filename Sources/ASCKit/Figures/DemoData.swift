import Foundation

/// Sample apps and figures for trying the app without a key: for App Review, screenshots, and anyone who wants to
/// see it before creating one. Invented, and the same every time for the same day.
public enum DemoData {
    public static let key = "demo"
    public static let days = 180

    public static var isOn: Bool {
        get { UserDefaults(suiteName: AppGroup.id)?.bool(forKey: key) ?? false }
        set { UserDefaults(suiteName: AppGroup.id)?.set(newValue, forKey: key) }
    }

    private struct Sample {
        public let name: String
        public let downloads: Double
        public let price: Double
        public let versions: [StoreApp.Version]
        /// The live version came out this many days ago; before, the reports show `previous`.
        public var released = 0
        public var previous = ""

        public var live: String { versions.first { $0.state == "READY_FOR_DISTRIBUTION" }?.string ?? "" }
    }

    private static let samples = [
        Sample(name: "Tideline – Tide Tables", downloads: 38, price: 2.99,
               versions: [.init(string: "2.4.0", state: "IN_REVIEW"), .init(string: "2.3.1", state: "READY_FOR_DISTRIBUTION")],
               released: 12, previous: "2.3.0"),
        Sample(name: "Moss – Habit Garden", downloads: 61, price: 0,
               versions: [.init(string: "1.8.2", state: "READY_FOR_DISTRIBUTION")], released: 40, previous: "1.8.1"),
        Sample(name: "Quillnote", downloads: 24, price: 4.99,
               versions: [.init(string: "3.0", state: "WAITING_FOR_REVIEW"), .init(string: "2.9.4", state: "READY_FOR_DISTRIBUTION")],
               released: 75, previous: "2.9.3"),
        Sample(name: "Kiln Timer", downloads: 12, price: 1.99,
               versions: [.init(string: "1.2", state: "READY_FOR_DISTRIBUTION")], released: 25, previous: "1.1"),
        Sample(name: "Fieldbook – Bird Log", downloads: 9, price: 0,
               versions: [.init(string: "1.0", state: "PREPARE_FOR_SUBMISSION")]),
    ]

    private static let countries: [(code: String, share: Double, currency: String, rate: Double)] = [
        ("US", 0.34, "USD", 1.0), ("DE", 0.16, "EUR", 0.92), ("GB", 0.11, "GBP", 0.79), ("JP", 0.08, "JPY", 150),
        ("FR", 0.07, "EUR", 0.92), ("CA", 0.06, "CAD", 1.36), ("AU", 0.05, "AUD", 1.52), ("NL", 0.04, "EUR", 0.92),
        ("CH", 0.03, "CHF", 0.88), ("SE", 0.03, "SEK", 10.6), ("BR", 0.03, "USD", 1.0),
    ]

    public static var apps: [StoreApp] {
        samples.enumerated().map { index, sample in
            StoreApp(id: "demo\(index)", name: sample.name, bundleID: "com.example.app\(index)", sku: "demo\(index)",
                     versions: sample.versions)
        }
    }

    public static func figures(now: Date = .now) -> Figures {
        var random = Random(seed: ReportDay.string(now).unicodeScalars.reduce(7) { $0 &* 31 &+ UInt64($1.value) })
        var reports: [String: [SalesRow]] = [:]
        var discovery: [DiscoveryRow] = []
        for (offset, day) in ReportDay.recent(Self.days, from: now).enumerated() {
            // A gentle rise towards today, with quieter weekends.
            let date = ReportDay.date(day) ?? now
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
            let trend = 0.75 + 0.5 * Double(Self.days - offset) / Double(Self.days)
            let weekend = weekday == 1 || weekday == 7 ? 0.8 : 1.0
            var rows: [SalesRow] = []
            for (index, sample) in samples.enumerated() where sample.versions.contains(where: { $0.state == "READY_FOR_DISTRIBUTION" }) {
                let total = sample.downloads * trend * weekend * random.next(0.7, 1.3)
                let version = offset < sample.released ? sample.live : sample.previous
                for country in countries {
                    let units = Int((total * country.share * random.next(0.5, 1.5)).rounded())
                    guard units > 0 else { continue }
                    let price = sample.price * country.rate
                    rows.append(SalesRow(title: sample.name, sku: "demo\(index)", appleID: "demo\(index)", parentSKU: "",
                                         productType: "1", units: units, proceeds: (price * 0.85 * 100).rounded() / 100,
                                         proceedsCurrency: price > 0 ? country.currency : "", country: country.code, device: "iPhone",
                                         version: version, customerPrice: (price * 100).rounded() / 100, customerCurrency: country.currency))
                }
                // Now and then someone asks for their money back.
                if sample.price > 0, random.next(0, 1) < 0.08 {
                    rows.append(SalesRow(title: sample.name, sku: "demo\(index)", appleID: "demo\(index)", parentSKU: "",
                                         productType: "1", units: -1, proceeds: (sample.price * 0.85 * 100).rounded() / 100,
                                         proceedsCurrency: "USD", country: "US", device: "iPhone", version: version))
                }
                let updates = Int(total * random.next(0.3, 0.8))
                if updates > 0 {
                    rows.append(SalesRow(title: sample.name, sku: "demo\(index)", appleID: "demo\(index)", parentSKU: "",
                                         productType: "7", units: updates, proceeds: 0, proceedsCurrency: "", country: "US", device: "iPhone",
                                         version: version))
                }
                // Store analytics lag two days behind the sales, as Apple's do.
                if offset >= 2 {
                    let seen = total * random.next(22, 34)
                    for (source, share) in [("App Store search", 0.58), ("App Store browse", 0.27), ("Web referrer", 0.09), ("App referrer", 0.06)] {
                        let impressions = Int(seen * share)
                        discovery.append(DiscoveryRow(date: day, appID: "demo\(index)", event: "Impression", pageType: "No page",
                                                      sourceType: source, engagementType: "", territory: "US",
                                                      counts: impressions, uniqueCounts: Int(Double(impressions) * 0.8)))
                        discovery.append(DiscoveryRow(date: day, appID: "demo\(index)", event: "Page view", pageType: "Product page",
                                                      sourceType: source, engagementType: "", territory: "US",
                                                      counts: Int(Double(impressions) * random.next(0.10, 0.16)), uniqueCounts: 0))
                    }
                }
            }
            reports[day] = rows
        }
        // Months and payouts: the apps' monthly totals, growing over the year; Moss sells a subscription.
        var months: [String: [SalesRow]] = [:]
        var payouts: [String: [FinanceRow]] = [:]
        for (age, month) in ReportDay.recentMonths(12, from: now).enumerated() {
            let growth = 0.55 + 0.45 * Double(12 - age) / 12
            var monthRows: [SalesRow] = []
            var earned = 0.0
            for (index, sample) in samples.enumerated() where sample.versions.contains(where: { $0.state == "READY_FOR_DISTRIBUTION" }) {
                let units = Int(sample.downloads * 30 * growth * random.next(0.85, 1.15))
                let proceeds = (sample.price * 0.85 * 100).rounded() / 100
                monthRows.append(SalesRow(title: sample.name, sku: "demo\(index)", appleID: "demo\(index)", parentSKU: "", productType: "1",
                                          units: units, proceeds: proceeds, proceedsCurrency: proceeds > 0 ? "USD" : "",
                                          country: "US", device: "iPhone"))
                earned += proceeds * Double(units)
            }
            months[month] = monthRows
            payouts[month] = [FinanceRow(title: "All apps", appleID: "", quantity: 0, amount: (earned * 100).rounded() / 100,
                                         currency: "USD", country: "US")]
        }
        let subscriptions = [
            SubscriptionRow(appID: "demo1", name: "Moss Plus Monthly", duration: "1 Month", proceeds: 2.54, currency: "USD",
                            country: "US", active: 184, trials: 23, offers: 0),
            SubscriptionRow(appID: "demo1", name: "Moss Plus Yearly", duration: "1 Year", proceeds: 21.24, currency: "USD",
                            country: "US", active: 412, trials: 0, offers: 9),
        ]
        // Crashes and sessions: a few sessions per download, Quillnote crashes a little more often than the rest.
        var usage: [UsageRow] = []
        for (day, rows) in reports {
            for app in apps {
                let downloads = rows.filter { $0.appleID == app.id || $0.appSKU == app.sku }.reduce(0) { $0 + max(0, $1.units) }
                let sessions = downloads * 9 + 40
                let rate = app.name.hasPrefix("Quillnote") ? 0.007 : 0.002
                usage.append(UsageRow(date: day, appID: app.id, crashes: Int((Double(sessions) * rate).rounded()), sessions: sessions))
            }
        }
        return Figures(apps: apps, days: reports, rates: Rates.cached(), discovery: discovery,
                       months: months, payouts: payouts, subscriptions: subscriptions, usage: usage)
    }

    public static func reviews(now: Date = .now) -> [Review] {
        let entries: [(app: Int, rating: Int, title: String, body: String, nickname: String, territory: String, daysAgo: Double)] = [
            (0, 5, "Finally tides that make sense", "Clean, fast, and the widget is exactly what I check before heading out.", "salt_and_sand", "USA", 0.4),
            (1, 5, "My plants and my habits", "Watching the garden grow keeps me going. Lovely little app.", "Jana K.", "DEU", 1.2),
            (2, 4, "Great editor", "Would love iCloud sync for folders, otherwise perfect for drafts.", "inkwell", "GBR", 2.5),
            (3, 5, "Does one thing well", "Set it, start the kiln, forget it. The alerts are reliable.", "potterybarnaby", "CAN", 4.1),
            (1, 4, "Gentle and motivating", "Streaks without the guilt. A dark mode toggle would be nice.", "mika", "JPN", 6.3),
        ]
        return entries.enumerated().map { index, entry in
            Review(id: "demo-review\(index)", appID: "demo\(entry.app)", rating: entry.rating, title: entry.title, body: entry.body,
                   nickname: entry.nickname, territory: entry.territory, date: now.addingTimeInterval(-entry.daysAgo * 86_400))
        }
    }

    /// The same numbers on every run of the same day.
    private struct Random {
        public var state: UInt64
        public init(seed: UInt64) { state = seed }
        public mutating func next(_ low: Double, _ high: Double) -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return low + (high - low) * Double(state >> 11) / Double(1 << 53)
        }
    }
}
