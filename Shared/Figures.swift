import Foundation

struct Figures {
    var apps: [StoreApp] = []
    /// Report day ("yyyy-MM-dd", Pacific) → its lines. Days Apple hasn't reported yet are missing.
    var days: [String: [SalesRow]] = [:]
    var rates = Rates.cached()
    /// How the apps were seen in the store (analytics). Empty until Apple delivers the first reports.
    var discovery: [DiscoveryRow] = []

    var latestDay: String? { days.keys.max() }

    var pending: [StoreApp] { apps.filter { $0.pending != nil } }

    func reportedDays(_ count: Int) -> [String] {
        Array(days.keys.sorted(by: >).prefix(count))
    }

    func rows(_ count: Int, app: StoreApp? = nil) -> [SalesRow] {
        reportedDays(count).flatMap { days[$0] ?? [] }.filter { belongs($0, to: app) }
    }

    func units(_ kind: SalesKind, days count: Int, app: StoreApp? = nil) -> Int {
        rows(count, app: app).filter { $0.kind == kind }.reduce(0) { $0 + $1.units }
    }

    /// Proceeds per currency; Apple reports each country's sales in its own currency.
    func proceeds(days count: Int, app: StoreApp? = nil) -> [String: Double] {
        Self.sums(rows(count, app: app))
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
            let units = (days[day] ?? []).filter { $0.kind == .download && belongs($0, to: app) }.reduce(0) { $0 + $1.units }
            return (date, units)
        }
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

    private func belongs(_ row: SalesRow, to app: StoreApp?) -> Bool {
        guard let app else { return true }
        return row.appSKU == app.sku || row.appleID == app.id
    }

    // MARK: Export

    /// One line per day and app: what the overview shows, for a spreadsheet.
    func dailyCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["Date", "App", "Downloads", "Updates", "Redownloads", "Proceeds (\(currency))", "Impressions", "Product page views"]]
        for day in reportedDays(count).reversed() {
            for app in apps {
                let sales = (days[day] ?? []).filter { belongs($0, to: app) }
                let store = discovery.filter { $0.date == day && $0.appID == app.id }
                let downloads = sales.filter { $0.kind == .download }.reduce(0) { $0 + $1.units }
                let updates = sales.filter { $0.kind == .update }.reduce(0) { $0 + $1.units }
                let redownloads = sales.filter { $0.kind == .redownload }.reduce(0) { $0 + $1.units }
                let impressions = store.filter { $0.event == "Impression" }.reduce(0) { $0 + $1.counts }
                let pageViews = store.filter { $0.event == "Page view" && $0.pageType == "Product page" }.reduce(0) { $0 + $1.counts }
                guard downloads + updates + redownloads + impressions + pageViews > 0 else { continue }
                lines.append([day, app.name, "\(downloads)", "\(updates)", "\(redownloads)",
                              Self.amount(rates.total(Self.sums(sales), in: currency).total), "\(impressions)", "\(pageViews)"])
            }
        }
        return Self.csv(lines)
    }

    /// One line per app and country over the period.
    func countriesCSV(days count: Int) -> String {
        let currency = DisplayCurrency.current
        var lines = [["App", "Country", "Downloads", "Proceeds (\(currency))"]]
        for app in apps {
            let byCountry = Dictionary(grouping: rows(count, app: app), by: \.country)
            for (country, sales) in byCountry.sorted(by: { $0.key < $1.key }) {
                let downloads = sales.filter { $0.kind == .download }.reduce(0) { $0 + $1.units }
                let proceeds = rates.total(Self.sums(sales), in: currency).total
                guard downloads > 0 || proceeds > 0 else { continue }
                lines.append([app.name, country, "\(downloads)", Self.amount(proceeds)])
            }
        }
        return Self.csv(lines)
    }

    private static func sums(_ rows: [SalesRow]) -> [String: Double] {
        rows.reduce(into: [:]) { sums, row in
            guard row.proceeds != 0, !row.proceedsCurrency.isEmpty else { return }
            sums[row.proceedsCurrency, default: 0] += row.proceeds * Double(row.units)
        }
    }

    /// A dot as the decimal separator, so every spreadsheet reads it as a number.
    private static func amount(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func csv(_ lines: [[String]]) -> String {
        lines.map { fields in
            fields.map { $0.contains(where: { ",\"\n".contains($0) }) ? "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : $0 }
                .joined(separator: ",")
        }.joined(separator: "\n") + "\n"
    }
}
