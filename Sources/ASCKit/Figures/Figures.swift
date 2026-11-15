import Foundation

public struct Figures: Sendable {
    public var apps: [StoreApp] = []
    /// Report day ("yyyy-MM-dd", Pacific) → its lines. Days Apple hasn't reported yet are missing.
    public var days: [String: [SalesRow]] = [:]
    public var rates = Rates.cached()
    /// How the apps were seen in the store (analytics). Empty until Apple delivers the first reports.
    public var discovery: [DiscoveryRow] = []
    /// Month ("yyyy-MM") → its monthly sales summary.
    public var months: [String: [SalesRow]] = [:]
    /// Fiscal month ("yyyy-MM") → what Apple's financial report says was earned.
    public var payouts: [String: [FinanceRow]] = [:]
    /// Active subscriptions as of the newest day Apple reported.
    public var subscriptions: [SubscriptionRow] = []

    public var latestDay: String? { days.keys.max() }

    public var pending: [StoreApp] { apps.filter { $0.pending != nil } }

    /// `count` reported days, newest first. `previous` takes the `count` days before those, for comparing.
    public func reportedDays(_ count: Int, previous: Bool = false) -> [String] {
        Array(days.keys.sorted(by: >).dropFirst(previous ? count : 0).prefix(count))
    }

    public func rows(_ count: Int, app: StoreApp? = nil, previous: Bool = false) -> [SalesRow] {
        reportedDays(count, previous: previous).flatMap { days[$0] ?? [] }.filter { belongs($0, to: app) }
    }

    /// Refunds are left out here and counted by `refunds`.
    public func units(_ kind: SalesKind, days count: Int, app: StoreApp? = nil, previous: Bool = false) -> Int {
        rows(count, app: app, previous: previous).filter { $0.kind == kind && !$0.isRefund }.reduce(0) { $0 + $1.units }
    }

    public func refunds(days count: Int, app: StoreApp? = nil) -> Int {
        -rows(count, app: app).filter(\.isRefund).reduce(0) { $0 + $1.units }
    }

    /// The change against the period before, e.g. 0.18 for 18 % more. Nil while the period before isn't complete.
    public func change(_ current: Double, _ previous: Double, days count: Int) -> Double? {
        guard reportedDays(count, previous: true).count == count, previous > 0 else { return nil }
        return current / previous - 1
    }

    /// Proceeds per currency; Apple reports each country's sales in its own currency.
    public func proceeds(days count: Int, app: StoreApp? = nil, previous: Bool = false) -> [String: Double] {
        Self.sums(rows(count, app: app, previous: previous))
    }

    /// The proceeds in the display currency, without the currencies the ECB doesn't list.
    public func proceedsTotal(days count: Int, app: StoreApp? = nil, previous: Bool = false) -> Double {
        rates.total(proceeds(days: count, app: app, previous: previous), in: DisplayCurrency.current).total
    }

    /// The proceeds as one amount in the display currency, e.g. "€1.98". Currencies the ECB doesn't list are added as they are.
    public func proceedsText(days count: Int, app: StoreApp? = nil) -> String {
        let target = DisplayCurrency.current
        let (total, rest) = rates.total(proceeds(days: count, app: app), in: target)
        return ([total.formatted(.currency(code: target))] + rest.sorted { $0.key < $1.key }.map { $0.value.formatted(.currency(code: $0.key)) })
            .joined(separator: " + ")
    }

    public func downloadsPerDay(_ count: Int, app: StoreApp? = nil) -> [(day: Date, units: Int)] {
        reportedDays(count).reversed().compactMap { day in
            guard let date = ReportDay.date(day) else { return nil }
            let units = (days[day] ?? []).filter { $0.kind == .download && !$0.isRefund && belongs($0, to: app) }.reduce(0) { $0 + $1.units }
            return (date, units)
        }
    }

    /// Downloads and proceeds of the last months, oldest first.
    public func monthly(app: StoreApp? = nil) -> [(month: Date, downloads: Int, proceeds: Double)] {
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
    public func payoutMonths() -> [(month: Date, amount: Double, expected: Date)] {
        payouts.keys.sorted(by: >).compactMap { month in
            guard let start = ReportDay.date(month + "-01"),
                  let end = Calendar(identifier: .gregorian).date(byAdding: DateComponents(month: 1, day: -1), to: start) else { return nil }
            let sums = (payouts[month] ?? []).reduce(into: [String: Double]()) { $0[$1.currency, default: 0] += $1.amount }
            return (start, rates.total(sums, in: DisplayCurrency.current).total, end.addingTimeInterval(33 * 86_400))
        }
    }

    // MARK: Subscriptions

    public func activeSubscriptions(app: StoreApp? = nil) -> Int {
        subscriptions.filter { app == nil || $0.appID == app!.id }.reduce(0) { $0 + $1.active + $1.offers }
    }

    public func trials(app: StoreApp? = nil) -> Int {
        subscriptions.filter { app == nil || $0.appID == app!.id }.reduce(0) { $0 + $1.trials }
    }

    /// Monthly recurring revenue: the proceeds of the paid subscriptions at their standard price, per month.
    public func monthlyRecurring(app: StoreApp? = nil) -> Double {
        let sums = subscriptions.filter { app == nil || $0.appID == app!.id }
            .reduce(into: [String: Double]()) { $0[$1.currency, default: 0] += $1.proceeds * Double($1.active) * $1.perMonth }
        return rates.total(sums, in: DisplayCurrency.current).total
    }

    /// The newest `count` days the analytics cover, newest first. They lag a day or two behind the sales.
    public func discoveryDays(_ count: Int) -> Set<String> {
        Set(Set(discovery.map(\.date)).sorted(by: >).prefix(count))
    }

    private func discoveryRows(_ count: Int, app: StoreApp?) -> [DiscoveryRow] {
        let days = discoveryDays(count)
        return discovery.filter { days.contains($0.date) && (app == nil || $0.appID == app!.id) }
    }

    /// The app's icon in a list: search results, charts, the Today tab.
    public func impressions(days count: Int, app: StoreApp? = nil, unique: Bool = false) -> Int {
        discoveryRows(count, app: app).filter { $0.event == "Impression" }.reduce(0) { $0 + (unique ? $1.uniqueCounts : $1.counts) }
    }

    public func pageViews(days count: Int, app: StoreApp? = nil) -> Int {
        discoveryRows(count, app: app).filter { $0.event == "Page view" && $0.pageType == "Product page" }.reduce(0) { $0 + $1.counts }
    }

    /// First-time downloads per person who saw the app, as Apple counts conversion. Nil without impressions.
    public func conversion(days count: Int, app: StoreApp? = nil) -> Double? {
        let seen = impressions(days: count, app: app, unique: true)
        guard seen > 0 else { return nil }
        return Double(units(.download, days: count, app: app)) / Double(seen)
    }

    public func sources(days count: Int, app: StoreApp? = nil) -> [(source: String, counts: Int)] {
        discoveryRows(count, app: app).filter { $0.event != "Tap" }
            .reduce(into: [String: Int]()) { $0[$1.sourceType.isEmpty ? "Unavailable" : $1.sourceType, default: 0] += $1.counts }
            .map { ($0.key, $0.value) }.sorted { $0.counts > $1.counts }
    }

    public func countries(days count: Int, app: StoreApp) -> [(country: String, units: Int)] {
        rows(count, app: app).filter { $0.kind == .download }
            .reduce(into: [String: Int]()) { $0[$1.country, default: 0] += $1.units }
            .map { ($0.key, $0.value) }.sorted { $0.units > $1.units }
    }

    public func belongs(_ row: SalesRow, to app: StoreApp?) -> Bool {
        guard let app else { return true }
        return row.appSKU == app.sku || row.appleID == app.id
    }

    // MARK: Releases and milestones

    /// The day each version first shows up in the sales reports, which is the day it went live. Versions already there on
    /// the oldest day are left out: they were released before.
    public func releases(app: StoreApp? = nil) -> [(app: StoreApp, version: String, day: Date)] {
        let sorted = days.keys.sorted()
        guard let oldest = sorted.first else { return [] }
        var firstSeen: [String: [String: String]] = [:]
        for day in sorted {
            for row in days[day] ?? [] where row.kind != .purchase && !(row.version ?? "").isEmpty {
                guard let owner = apps.first(where: { belongs(row, to: $0) }), app == nil || owner.id == app!.id else { continue }
                if firstSeen[owner.id]?[row.version!] == nil { firstSeen[owner.id, default: [:]][row.version!] = day }
            }
        }
        return apps.flatMap { app in
            (firstSeen[app.id] ?? [:]).compactMap { version, day in
                day == oldest ? nil : ReportDay.date(day).map { (app, version, $0) }
            }
        }
        .sorted { $0.day < $1.day }
    }

    /// "yyyy-MM-dd" + app ID → the versions released that day, for the exports.
    public func releasesByDay() -> [String: String] {
        releases().reduce(into: [:]) { result, release in
            let key = ReportDay.string(release.day) + release.app.id
            result[key] = [result[key], release.version].compactMap(\.self).joined(separator: " ")
        }
    }

    /// First-time downloads since the app came out, as far as the reports reach: Apple's monthly summaries
    /// for the last twelve months, and the daily reports for the days after them.
    public func lifetimeDownloads(app: StoreApp) -> Int {
        let monthly = months.values.joined().filter { belongs($0, to: app) && $0.kind == .download && !$0.isRefund }
            .reduce(0) { $0 + $1.units }
        let newestMonth = months.keys.max() ?? ""
        let daily = days.filter { String($0.key.prefix(7)) > newestMonth }.values.joined()
            .filter { belongs($0, to: app) && $0.kind == .download && !$0.isRefund }.reduce(0) { $0 + $1.units }
        return monthly + daily
    }

    // MARK: Countries

    /// What a first-time download brought in per country, in the display currency. Countries without downloads are left out.
    public func proceedsPerDownload(days count: Int, app: StoreApp? = nil) -> [String: Double] {
        let byCountry = Dictionary(grouping: rows(count, app: app), by: \.country)
        return byCountry.compactMapValues { rows in
            let downloads = Self.units(rows).downloads
            guard downloads > 0 else { return nil }
            return rates.total(Self.sums(rows), in: DisplayCurrency.current).total / Double(downloads)
        }
    }

    // MARK: Export

    /// One line per day and app: what the overview shows, for a spreadsheet.
    public func dailyCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        let released = releasesByDay()
        var lines = [["Date", "App", "Release", "Downloads", "Updates", "Redownloads", "Refunds", "Proceeds (\(currency))",
                      "Impressions", "Product page views"]]
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
                lines.append([day, app.name, released[day + app.id] ?? "", "\(downloads)", "\(updates)", "\(redownloads)", "\(refunds)",
                              Self.amount(rates.total(Self.sums(sales), in: currency).total), "\(impressions)", "\(pageViews)"])
            }
        }
        return Self.csv(lines)
    }

    /// One line per app and country over the period.
    public func countriesCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["App", "Country", "Country code", "Downloads", "Updates", "Redownloads", "Refunds", "Proceeds (\(currency))",
                      "Proceeds per download (\(currency))"]]
        for app in apps {
            let byCountry = Dictionary(grouping: rows(count, app: app), by: \.country)
            for (country, sales) in byCountry.sorted(by: { $0.key < $1.key }) {
                let units = Self.units(sales)
                let proceeds = rates.total(Self.sums(sales), in: currency).total
                guard units.downloads + units.updates + units.redownloads + units.refunds > 0 || proceeds != 0 else { continue }
                lines.append([app.name, Self.countryName(country), country, "\(units.downloads)", "\(units.updates)",
                              "\(units.redownloads)", "\(units.refunds)", Self.amount(proceeds),
                              units.downloads > 0 ? Self.amount(proceeds / Double(units.downloads)) : ""])
            }
        }
        return Self.csv(lines)
    }

    /// Every line of Apple's daily reports in the period, for pivot tables: day, app, country, device and product.
    public func salesCSV(days count: Int) -> String {
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
    public func storeCSV(days count: Int) -> String {
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

    public static func countryName(_ code: String) -> String {
        code.count == 2 ? Locale.current.localizedString(forRegionCode: code) ?? code : code
    }

    public static func units(_ rows: [SalesRow]) -> (downloads: Int, updates: Int, redownloads: Int, refunds: Int) {
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

    public static func sums(_ rows: [SalesRow]) -> [String: Double] {
        rows.reduce(into: [:]) { sums, row in
            guard row.proceeds != 0, !row.proceedsCurrency.isEmpty else { return }
            sums[row.proceedsCurrency, default: 0] += row.proceeds * Double(row.units)
        }
    }

    /// Spreadsheets read a CSV the way the region's spreadsheets write one: where the decimal separator is a comma,
    /// as in Germany, fields are separated by semicolons.
    private static var decimalComma: Bool { Locale.current.decimalSeparator == "," }

    public static func amount(_ value: Double) -> String {
        let text = String(format: "%.2f", value)
        return decimalComma ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    /// Starts with a byte order mark, without which Excel reads UTF-8 as an older encoding and garbles "–" and umlauts.
    public static func csv(_ lines: [[String]]) -> String {
        let separator = decimalComma ? ";" : ","
        return "\u{FEFF}" + lines.map { fields in
            fields.map { $0.contains(where: { (separator + "\"\n").contains($0) }) ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }
                .joined(separator: separator)
        }.joined(separator: "\n") + "\n"
    }
}
