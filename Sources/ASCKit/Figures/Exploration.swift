import Foundation

/// What the Explore tab can chart: a metric over days, split by one dimension.
public enum Metric: String, CaseIterable, Identifiable, Codable, Sendable {
    case downloads, proceeds, updates, redownloads, refunds, impressions, pageViews

    public var id: Self { self }

    public var title: String {
        switch self {
        case .downloads: "Downloads"
        case .proceeds: "Proceeds"
        case .updates: "Updates"
        case .redownloads: "Re-downloads"
        case .refunds: "Refunds"
        case .impressions: "Impressions"
        case .pageViews: "Page views"
        }
    }

    /// From Apple's store analytics rather than the sales reports.
    public var isStore: Bool { self == .impressions || self == .pageViews }

    public var splits: [Split] {
        isStore ? [.none, .app, .country, .source] : [.none, .app, .country, .device]
    }
}

public enum Split: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, app, country, device, source

    public var id: Self { self }

    public var title: String {
        switch self {
        case .none: "None"
        case .app: "App"
        case .country: "Country"
        case .device: "Device"
        case .source: "Source"
        }
    }
}

public struct Exploration {
    public struct Point: Identifiable {
        public let day: Date
        public let group: String
        public let value: Double

        public var id: String { "\(day.timeIntervalSince1970)|\(group)" }
    }

    /// One point per day and group, oldest first.
    public let points: [Point]
    /// Each group's total over the period, largest first.
    public let totals: [(group: String, value: Double)]

    /// The largest groups by name, the rest folded into "Other" so the chart stays readable. Each day stacks them
    /// in the same order, the largest at the bottom.
    public func charted(top: Int = 5) -> [Point] {
        let order = Dictionary(uniqueKeysWithValues: chartedGroups(top: top).enumerated().map { ($1, $0) })
        let folded = Dictionary(grouping: points) { "\($0.day.timeIntervalSince1970)|\(order[$0.group] == nil ? Self.other : $0.group)" }
            .map { _, points in Point(day: points[0].day, group: order[points[0].group] == nil ? Self.other : points[0].group,
                                      value: points.reduce(0) { $0 + $1.value }) }
        return folded.sorted { ($0.day, order[$0.group] ?? top) < ($1.day, order[$1.group] ?? top) }
    }

    /// The groups in the chart's order: largest first, "Other" last.
    public func chartedGroups(top: Int = 5) -> [String] {
        totals.prefix(top).map(\.group) + (totals.count > top ? [Self.other] : [])
    }

    public static let other = "Other"
}

extension Figures {
    public func explore(_ metric: Metric, by split: Split, days count: Int, app: StoreApp? = nil) -> Exploration {
        var values: [String: [String: Double]] = [:]
        if metric.isStore {
            let days = discoveryDays(count)
            for row in discovery where days.contains(row.date) && (app == nil || row.appID == app!.id) {
                guard metric == .impressions ? row.event == "Impression" : row.event == "Page view" && row.pageType == "Product page"
                else { continue }
                values[row.date, default: [:]][group(of: row, by: split, metric: metric), default: 0] += Double(row.counts)
            }
        } else {
            for day in reportedDays(count) {
                for row in days[day] ?? [] where belongs(row, to: app) {
                    guard let value = value(of: row, metric) else { continue }
                    values[day, default: [:]][group(of: row, by: split, metric: metric), default: 0] += value
                }
            }
        }
        let points = values.keys.sorted().flatMap { day in
            (values[day] ?? [:]).compactMap { group, value in ReportDay.date(day).map { Exploration.Point(day: $0, group: group, value: value) } }
        }
        let totals = points.reduce(into: [String: Double]()) { $0[$1.group, default: 0] += $1.value }
            .map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        return Exploration(points: points, totals: totals)
    }

    private func value(of row: SalesRow, _ metric: Metric) -> Double? {
        switch metric {
        case .downloads: row.kind == .download && !row.isRefund ? Double(row.units) : nil
        case .updates: row.kind == .update ? Double(row.units) : nil
        case .redownloads: row.kind == .redownload ? Double(row.units) : nil
        case .refunds: row.isRefund ? Double(-row.units) : nil
        case .proceeds:
            row.proceeds != 0 && !row.proceedsCurrency.isEmpty
                ? rates.total([row.proceedsCurrency: row.proceeds * Double(row.units)], in: DisplayCurrency.current).total : nil
        case .impressions, .pageViews: nil
        }
    }

    private func group(of row: SalesRow, by split: Split, metric: Metric) -> String {
        switch split {
        case .none, .source: metric.title
        case .app: apps.first { belongs(row, to: $0) }?.name ?? row.title
        case .country: Self.countryName(row.country)
        case .device: row.device.isEmpty ? "Unknown" : row.device
        }
    }

    private func group(of row: DiscoveryRow, by split: Split, metric: Metric) -> String {
        switch split {
        case .none, .device: metric.title
        case .app: apps.first { $0.id == row.appID }?.name ?? row.appID
        case .country: Self.countryName(row.territory)
        case .source: row.sourceType.isEmpty ? "Unavailable" : row.sourceType
        }
    }

    /// The average day per weekday, Monday first. Days without anything count as 0, so a quiet Sunday shows.
    public func weekdays(_ metric: Metric, days count: Int, app: StoreApp? = nil) -> [(weekday: String, average: Double)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ReportDay.timeZone
        calendar.locale = .current
        let covered = (metric.isStore ? Array(discoveryDays(count)) : reportedDays(count)).compactMap(ReportDay.date)
        guard !covered.isEmpty else { return [] }
        var totals = [Double](repeating: 0, count: 7), counts = [Int](repeating: 0, count: 7)
        let values = explore(metric, by: .none, days: count, app: app).points.reduce(into: [Date: Double]()) { $0[$1.day, default: 0] += $1.value }
        for day in covered {
            let index = (calendar.component(.weekday, from: day) + 5) % 7
            totals[index] += values[day] ?? 0
            counts[index] += 1
        }
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { index in (symbols[(index + 1) % 7], counts[index] > 0 ? totals[index] / Double(counts[index]) : 0) }
    }

    /// Every metric that can be split this way, one column each, so the file holds more than the chart.
    /// The store analytics lag behind the sales, so a day either source hasn't covered yet stays empty rather than 0.
    public func exploreCSV(by split: Split, days count: Int, app: StoreApp?) -> String {
        let metrics = Metric.allCases.filter { $0.splits.contains(split) }
        // One line per app as well, unless the split already is the app.
        let perApp = split != .app
        let scopes: [StoreApp?] = perApp ? app.map { [$0] } ?? apps : [app]
        var values: [String: [Metric: Double]] = [:]
        for metric in metrics {
            for app in scopes {
                for point in explore(metric, by: split, days: count, app: app).points {
                    let key = [ReportDay.string(point.day)] + (perApp ? [app?.name ?? ""] : []) + (split == .none ? [] : [point.group])
                    values[key.joined(separator: "\t"), default: [:]][metric] = point.value
                }
            }
        }
        let salesDays = Set(reportedDays(count)), storeDays = discoveryDays(count)
        let header = metrics.map { $0 == .proceeds ? "\($0.title) (\(DisplayCurrency.current))" : $0.title }
        // Every line is one app's (by the app column, or by the split), so it can say which version came out that day.
        let released = releasesByDay()
        let ids = Dictionary(apps.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        var lines = [["Date"] + (perApp ? ["App"] : []) + (split == .none ? [] : [split.title]) + ["Release"] + header]
        for key in values.keys.sorted() {
            var parts = key.components(separatedBy: "\t")
            parts.append(ids[parts[1]].flatMap { released[parts[0] + $0] } ?? "")
            let columns = metrics.map { metric in
                guard (metric.isStore ? storeDays : salesDays).contains(parts[0]) else { return "" }
                let value = values[key]?[metric] ?? 0
                return metric == .proceeds ? Self.amount(value) : String(Int(value))
            }
            lines.append(parts + columns)
        }
        return Self.csv(lines)
    }
}
