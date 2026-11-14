import Foundation

struct Figures {
    var apps: [StoreApp] = []
    /// Report day ("yyyy-MM-dd", Pacific) → its lines. Days Apple hasn't reported yet are missing.
    var days: [String: [SalesRow]] = [:]
    var rates = Rates.cached()
    /// How the apps were seen in the store (analytics). Empty until Apple delivers the first reports.
    var discovery: [DiscoveryRow] = []
    /// Month ("yyyy-MM") → its monthly sales summary.
    var months: [String: [SalesRow]] = [:]
    /// Fiscal month ("yyyy-MM") → what Apple's financial report says was earned.
    var payouts: [String: [FinanceRow]] = [:]
    /// Active subscriptions as of the newest day Apple reported.
    var subscriptions: [SubscriptionRow] = []

    var latestDay: String? { days.keys.max() }

    var pending: [StoreApp] { apps.filter { $0.pending != nil } }

    /// `count` reported days, newest first. `previous` takes the `count` days before those, for comparing.
    func reportedDays(_ count: Int, previous: Bool = false) -> [String] {
        Array(days.keys.sorted(by: >).dropFirst(previous ? count : 0).prefix(count))
    }

    func rows(_ count: Int, app: StoreApp? = nil, previous: Bool = false) -> [SalesRow] {
        reportedDays(count, previous: previous).flatMap { days[$0] ?? [] }.filter { belongs($0, to: app) }
    }

    /// Refunds are left out here and counted by `refunds`.
    func units(_ kind: SalesKind, days count: Int, app: StoreApp? = nil, previous: Bool = false) -> Int {
        rows(count, app: app, previous: previous).filter { $0.kind == kind && !$0.isRefund }.reduce(0) { $0 + $1.units }
    }

    func refunds(days count: Int, app: StoreApp? = nil) -> Int {
        -rows(count, app: app).filter(\.isRefund).reduce(0) { $0 + $1.units }
    }

    /// The change against the period before, e.g. 0.18 for 18 % more. Nil while the period before isn't complete.
    func change(_ current: Double, _ previous: Double, days count: Int) -> Double? {
        guard reportedDays(count, previous: true).count == count, previous > 0 else { return nil }
        return current / previous - 1
    }

    /// Proceeds per currency; Apple reports each country's sales in its own currency.
    func proceeds(days count: Int, app: StoreApp? = nil, previous: Bool = false) -> [String: Double] {
        Self.sums(rows(count, app: app, previous: previous))
    }

    /// The proceeds in the display currency, without the currencies the ECB doesn't list.
    func proceedsTotal(days count: Int, app: StoreApp? = nil, previous: Bool = false) -> Double {
        rates.total(proceeds(days: count, app: app, previous: previous), in: DisplayCurrency.current).total
    }

    /// The proceeds as one amount in the display currency, e.g. "€1.98". Currencies the ECB doesn't list are added as they are.
    func proceedsText(days count: Int, app: StoreApp? = nil) -> String {
        let target = DisplayCurrency.current
        let (total, rest) = rates.total(proceeds(days: count, app: app), in: target)
        return ([total.formatted(.currency(code: target))] + rest.sorted { $0.key < $1.key }.map { $0.value.formatted(.currency(code: $0.key)) })
            .joined(separator: " + ")
    }

    func downloadsPerDay(_ count: Int, app: StoreApp? = nil) -> [(day: Date, units: Int)] {
        reportedDays(count).reversed().compactMap { day in
            guard let date = ReportDay.date(day) else { return nil }
            let units = (days[day] ?? []).filter { $0.kind == .download && !$0.isRefund && belongs($0, to: app) }.reduce(0) { $0 + $1.units }
            return (date, units)
        }
    }

    /// Downloads and proceeds of the last months, oldest first.
    func monthly(app: StoreApp? = nil) -> [(month: Date, downloads: Int, proceeds: Double)] {
        months.keys.sorted().compactMap { month in
            guard let date = ReportDay.date(month + "-01") else { return nil }
            let rows = (months[month] ?? []).filter { belongs($0, to: app) }
            let downloads = rows.filter { $0.kind == .download && !$0.isRefund }.reduce(0) { $0 + $1.units }
            return (date, downloads, rates.total(Self.sums(rows), in: DisplayCurrency.current).total)
        }
    }

    // MARK: Payouts

    /// What Apple's financial reports say each fiscal month earned, newest first, in the display currency.
    /// Apple pays a month within 33 days of its end, into the account's bank currency at Apple's own rate.
    func payoutMonths() -> [(month: Date, amount: Double, expected: Date)] {
        payouts.keys.sorted(by: >).compactMap { month in
            guard let start = ReportDay.date(month + "-01"),
                  let end = Calendar(identifier: .gregorian).date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
            let sums = (payouts[month] ?? []).reduce(into: [String: Double]()) { $0[$1.currency, default: 0] += $1.amount }
            return (start, rates.total(sums, in: DisplayCurrency.current).total, end.addingTimeInterval(33 * 86_400))
        }
    }

    // MARK: Subscriptions

    func activeSubscriptions(app: StoreApp? = nil) -> Int {
        subscriptions.filter { app == nil || $0.appID == app!.id }.reduce(0) { $0 + $1.active + $1.offers }
    }

    func trials(app: StoreApp? = nil) -> Int {
        subscriptions.filter { app == nil || $0.appID == app!.id }.reduce(0) { $0 + $1.trials }
    }

    /// Monthly recurring revenue: the proceeds of the paid subscriptions at their standard price, per month.
    func monthlyRecurring(app: StoreApp? = nil) -> Double {
        let sums = subscriptions.filter { app == nil || $0.appID == app!.id }
            .reduce(into: [String: Double]()) { $0[$1.currency, default: 0] += $1.proceeds * Double($1.active) * $1.perMonth }
        return rates.total(sums, in: DisplayCurrency.current).total
    }

    /// The newest `count` days the analytics cover, newest first. They lag a day or two behind the sales.
    func discoveryDays(_ count: Int) -> Set<String> {
        Set(Set(discovery.map(\.date)).sorted(by: >).prefix(count))
    }

    private func discoveryRows(_ count: Int, app: StoreApp?) -> [DiscoveryRow] {
        let days = discoveryDays(count)
        return discovery.filter { days.contains($0.date) && (app == nil || $0.appID == app!.id) }
    }

    /// The app's icon in a list: search results, charts, the Today tab.
    func impressions(days count: Int, app: StoreApp? = nil, unique: Bool = false) -> Int {
        discoveryRows(count, app: app).filter { $0.event == "Impression" }.reduce(0) { $0 + (unique ? $1.uniqueCounts : $1.counts) }
    }

    func pageViews(days count: Int, app: StoreApp? = nil) -> Int {
        discoveryRows(count, app: app).filter { $0.event == "Page view" && $0.pageType == "Product page" }.reduce(0) { $0 + $1.counts }
    }

    /// First-time downloads per person who saw the app, as Apple counts conversion. Nil without impressions.
    func conversion(days count: Int, app: StoreApp? = nil) -> Double? {
        let seen = impressions(days: count, app: app, unique: true)
        guard seen > 0 else { return nil }
        return Double(units(.download, days: count, app: app)) / Double(seen)
    }

    func sources(days count: Int, app: StoreApp? = nil) -> [(source: String, counts: Int)] {
        discoveryRows(count, app: app).filter { $0.event != "Tap" }
            .reduce(into: [String: Int]()) { $0[$1.sourceType.isEmpty ? "Unavailable" : $1.sourceType, default: 0] += $1.counts }
            .map { ($0.key, $0.value) }.sorted { $0.counts > $1.counts }
    }

    func countries(days count: Int, app: StoreApp) -> [(country: String, units: Int)] {
        rows(count, app: app).filter { $0.kind == .download }
            .reduce(into: [String: Int]()) { $0[$1.country, default: 0] += $1.units }
            .map { ($0.key, $0.value) }.sorted { $0.units > $1.units }
    }

    func belongs(_ row: SalesRow, to app: StoreApp?) -> Bool {
        guard let app else { return true }
        return row.appSKU == app.sku || row.appleID == app.id
    }

    // MARK: Export

    /// One line per day and app: what the overview shows, for a spreadsheet.
    func dailyCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["Date", "App", "Downloads", "Updates", "Redownloads", "Refunds", "Proceeds (\(currency))", "Impressions", "Product page views"]]
        for day in reportedDays(count).reversed() {
            for app in apps {
                let sales = (days[day] ?? []).filter { belongs($0, to: app) }
                let store = discovery.filter { $0.date == day && $0.appID == app.id }
                let downloads = sales.filter { $0.kind == .download && !$0.isRefund }.reduce(0) { $0 + $1.units }
                let updates = sales.filter { $0.kind == .update }.reduce(0) { $0 + $1.units }
                let redownloads = sales.filter { $0.kind == .redownload }.reduce(0) { $0 + $1.units }
                let refunds = -sales.filter(\.isRefund).reduce(0) { $0 + $1.units }
                let impressions = store.filter { $0.event == "Impression" }.reduce(0) { $0 + $1.counts }
                let pageViews = store.filter { $0.event == "Page view" && $0.pageType == "Product page" }.reduce(0) { $0 + $1.counts }
                guard downloads + updates + redownloads + refunds + impressions + pageViews > 0 else { continue }
                lines.append([day, app.name, "\(downloads)", "\(updates)", "\(redownloads)", "\(refunds)",
                              Self.amount(rates.total(Self.sums(sales), in: currency).total), "\(impressions)", "\(pageViews)"])
            }
        }
        return Self.csv(lines)
    }

    /// One line per app and country over the period.
    func countriesCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["App", "Country", "Country code", "Downloads", "Updates", "Redownloads", "Refunds", "Proceeds (\(currency))"]]
        for app in apps {
            let byCountry = Dictionary(grouping: rows(count, app: app), by: \.country)
            for (country, sales) in byCountry.sorted(by: { $0.key < $1.key }) {
                let units = Self.units(sales)
                let proceeds = rates.total(Self.sums(sales), in: currency).total
                guard units.downloads + units.updates + units.redownloads + units.refunds > 0 || proceeds != 0 else { continue }
                lines.append([app.name, Self.countryName(country), country, "\(units.downloads)", "\(units.updates)",
                              "\(units.redownloads)", "\(units.refunds)", Self.amount(proceeds)])
            }
        }
        return Self.csv(lines)
    }

    /// Every line of Apple's daily reports in the period, for pivot tables: day, app, country, device and product.
    func salesCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["Date", "App", "Product", "Version", "Type", "Country", "Device", "Units", "Customer price",
                      "Customer currency", "Proceeds per unit", "Currency", "Proceeds (\(currency))"]]
        for day in reportedDays(count).reversed() {
            for row in (days[day] ?? []).sorted(by: { ($0.appSKU, $0.country, $0.device) < ($1.appSKU, $1.country, $1.device) }) {
                let app = apps.first { belongs(row, to: $0) }?.name ?? row.title
                let total = row.proceedsCurrency.isEmpty ? 0
                    : rates.total([row.proceedsCurrency: row.proceeds * Double(row.units)], in: currency).total
                lines.append([day, app, row.title, row.version ?? "", row.isRefund ? "refund" : row.kind.rawValue, row.country,
                              row.device, "\(row.units)", row.customerPrice.map(Self.amount) ?? "", row.customerCurrency ?? "",
                              Self.amount(row.proceeds), row.proceedsCurrency, Self.amount(total)])
            }
        }
        return Self.csv(lines)
    }

    /// Apple's store analytics in the period: per day, app, source and country.
    func storeCSV(days count: Int) -> String {
        let days = discoveryDays(count)
        var sums: [[String]: (impressions: Int, unique: Int, pageViews: Int)] = [:]
        for row in discovery where days.contains(row.date) {
            let key = [row.date, apps.first { $0.id == row.appID }?.name ?? row.appID,
                       row.sourceType.isEmpty ? "Unavailable" : row.sourceType, row.territory]
            if row.event == "Impression" {
                sums[key, default: (0, 0, 0)].impressions += row.counts
                sums[key, default: (0, 0, 0)].unique += row.uniqueCounts
            } else if row.event == "Page view" && row.pageType == "Product page" {
                sums[key, default: (0, 0, 0)].pageViews += row.counts
            }
        }
        let lines = [["Date", "App", "Source", "Country", "Impressions", "Unique impressions", "Product page views"]]
            + sums.keys.sorted { $0.lexicographicallyPrecedes($1) }.map { key in
                let sum = sums[key]!
                return key + ["\(sum.impressions)", "\(sum.unique)", "\(sum.pageViews)"]
            }
        return Self.csv(lines)
    }

    static func countryName(_ code: String) -> String {
        code.count == 2 ? Locale.current.localizedString(forRegionCode: code) ?? code : code
    }

    private static func units(_ rows: [SalesRow]) -> (downloads: Int, updates: Int, redownloads: Int, refunds: Int) {
        rows.reduce(into: (0, 0, 0, 0)) { sums, row in
            if row.isRefund { sums.3 -= row.units; return }
            switch row.kind {
            case .download: sums.0 += row.units
            case .update: sums.1 += row.units
            case .redownload: sums.2 += row.units
            case .purchase, .other: break
            }
        }
    }

    private static func sums(_ rows: [SalesRow]) -> [String: Double] {
        rows.reduce(into: [:]) { sums, row in
            guard row.proceeds != 0, !row.proceedsCurrency.isEmpty else { return }
            sums[row.proceedsCurrency, default: 0] += row.proceeds * Double(row.units)
        }
    }

    /// A dot as the decimal separator, so every spreadsheet reads it as a number.
    static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func csv(_ lines: [[String]]) -> String {
        lines.map { fields in
            fields.map { $0.contains(where: { ",\"\n".contains($0) }) ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }
                .joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}
