import Charts
import SwiftUI
import WidgetKit

@main
struct AppSalesWidgets: WidgetBundle {
    var body: some Widget {
        SalesWidget()
    }
}

struct SalesEntry: TimelineEntry {
    var date: Date
    var figures: Figures
    var isSetUp: Bool
}

/// Fetches on its own: yesterday's report arrives in the morning, and the widget shows it without
/// the app being opened. Days already on disk (from the app or an earlier run) aren't fetched again.
struct SalesProvider: TimelineProvider {
    func placeholder(in context: Context) -> SalesEntry {
        SalesEntry(date: .now, figures: Figures(), isSetUp: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SalesEntry) -> Void) {
        completion(DemoData.isOn ? SalesEntry(date: .now, figures: DemoData.figures(), isSetUp: true) : cached())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SalesEntry>) -> Void) {
        // WidgetKit calls it once and doesn't touch it again until it's called back.
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await fetch()
            // Apple's reports come once a day; every three hours is enough to catch the new one early.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3 * 3600))))
        }
    }

    private func cached() -> SalesEntry {
        let days = ReportDay.recent(7).reduce(into: [String: [SalesRow]]()) { $0[$1] = ReportCache.load($1) }
        return SalesEntry(date: .now, figures: Figures(apps: ReportCache.loadApps(), days: days), isSetUp: KeyStore.load() != nil)
    }

    private func fetch() async -> SalesEntry {
        if DemoData.isOn { return SalesEntry(date: .now, figures: DemoData.figures(), isSetUp: true) }
        guard let account = KeyStore.load(), let client = try? Client(key: account.key) else { return cached() }
        var figures = cached().figures
        if let apps = try? await client.apps() {
            figures.apps = apps
            ReportCache.saveApps(apps)
        }
        if let days = try? await ReportCache.days(ReportDay.recent(7), client: client, vendor: account.vendorNumber) {
            figures.days = days
        }
        figures.rates = await Rates.current()
        return SalesEntry(date: .now, figures: figures, isSetUp: true)
    }
}

struct SalesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sales", provider: SalesProvider()) { entry in
            SalesWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.ground }
        }
        .configurationDisplayName("Downloads")
        .description("Yesterday's downloads and the last 7 days, over all your apps.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct SalesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SalesEntry

    private var yesterday: Int { entry.figures.units(.download, days: 1) }
    private var week: Int { entry.figures.units(.download, days: 7) }

    var body: some View {
        if !entry.isSetUp {
            Text("Open App Sales to connect your key.").font(.caption).foregroundStyle(Color.muted)
        } else {
            switch family {
            case .accessoryInline:
                Text("↓ \(yesterday) yesterday · \(week) in 7 days")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("App Sales").font(.caption2.weight(.semibold))
                    Text("\(yesterday) downloads yesterday").font(.caption)
                    Text("\(week) in 7 days").font(.caption).foregroundStyle(.secondary)
                }
            case .systemMedium:
                HStack(spacing: 14) {
                    totals
                    chart
                }
            default:
                totals
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Yesterday").font(.caption).foregroundStyle(Color.muted)
            Text("\(yesterday)").font(.system(size: 40, weight: .semibold)).monospacedDigit()
                .minimumScaleFactor(0.5).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(week) in 7 days").font(.caption.weight(.medium))
            Text(entry.figures.proceedsText(days: 7)).font(.caption2).foregroundStyle(Color.muted).lineLimit(1)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chart: some View {
        Chart(entry.figures.downloadsPerDay(7), id: \.day) { point in
            BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.units))
                .foregroundStyle(Color.sales)
                .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
    }
}
