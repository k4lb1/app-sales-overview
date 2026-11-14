import Charts
import SwiftUI

/// A chart put together by hand: one metric over the days, split by app, country, device or store source.
struct ExploreView: View {
    @Environment(Dashboard.self) private var dashboard
    @AppStorage("explore.metric") private var metric = Metric.downloads
    @AppStorage("explore.split") private var split = Split.country
    @AppStorage("explore.period") private var period = 30
    @State private var appID: String?

    private var app: StoreApp? { dashboard.figures.apps.first { $0.id == appID } }
    private var exploration: Exploration { dashboard.figures.explore(metric, by: split, days: period, app: app) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                choices
                Picker("Period", selection: $period) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                }
                .pickerStyle(.segmented)

                let exploration = exploration
                if exploration.points.isEmpty {
                    ContentUnavailableView(
                        "Nothing to show yet", systemImage: "chart.bar",
                        description: Text(metric.isStore
                                          ? "Apple's store analytics arrive a day or two after the sales, the first ones one to two days after you connect."
                                          : "There's nothing for \(metric.title.lowercased()) in this period."))
                        .frame(maxWidth: .infinity).card()
                } else {
                    chart(exploration)
                    if split != .none { ranking(exploration) }
                }
            }
            .padding(16)
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle("Explore")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: CSVFile(name: fileName, text: dashboard.figures.exploreCSV(metric, by: split, days: period, app: app)),
                          preview: SharePreview(fileName)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Export as CSV")
            }
        }
        .onChange(of: metric) { _, metric in
            if !metric.splits.contains(split) { split = .none }
        }
    }

    private var choices: some View {
        VStack(spacing: 0) {
            row("Metric") {
                Picker("Metric", selection: $metric) {
                    Section("Sales") { ForEach(Metric.allCases.filter { !$0.isStore }) { Text($0.title).tag($0) } }
                    Section("Store") { ForEach(Metric.allCases.filter(\.isStore)) { Text($0.title).tag($0) } }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            row("Split by") {
                Picker("Split by", selection: $split) {
                    ForEach(metric.splits) { Text($0.title).tag($0) }
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
            row("Apps") {
                Picker("Apps", selection: $appID) {
                    Text("All apps").tag(String?.none)
                    ForEach(dashboard.figures.apps) { Text($0.name).tag(Optional($0.id)) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .background(Color.card, in: .rect(cornerRadius: 20))
    }

    private func row(_ title: LocalizedStringKey, @ViewBuilder picker: () -> some View) -> some View {
        HStack {
            Text(title).foregroundStyle(Color.muted)
            Spacer()
            picker().pickerStyle(.menu).labelsHidden()
        }
        .frame(minHeight: 44)
    }

    private func chart(_ exploration: Exploration) -> some View {
        let groups = exploration.chartedGroups()
        return VStack(alignment: .leading, spacing: 10) {
            Text(total(exploration)).font(.title.weight(.semibold)).monospacedDigit()
            Chart(exploration.charted()) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value(metric.title, point.value))
                    .foregroundStyle(by: .value(split.title, point.group))
            }
            .chartForegroundStyleScale(domain: groups, range: Self.shades(groups.count))
            .chartLegend(split == .none ? .hidden : .visible)
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 200)
        }
        .card()
    }

    private func ranking(_ exploration: Exploration) -> some View {
        let largest = exploration.totals.first?.value ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("By \(split.title.lowercased())").font(.headline)
            ForEach(exploration.totals.prefix(20), id: \.group) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.group).lineLimit(1)
                        Spacer()
                        Text(formatted(entry.value)).monospacedDigit()
                    }
                    GeometryReader { proxy in
                        Capsule().fill(Color.sales).frame(width: max(2, proxy.size.width * entry.value / max(largest, 1)))
                    }
                    .frame(height: 4)
                }
            }
            if exploration.totals.count > 20 {
                Text("and \(exploration.totals.count - 20) more in the export").font(.caption).foregroundStyle(Color.muted)
            }
        }
        .card()
    }

    private func total(_ exploration: Exploration) -> String {
        formatted(exploration.totals.reduce(0) { $0 + $1.value })
    }

    private func formatted(_ value: Double) -> String {
        metric == .proceeds ? value.formatted(.currency(code: DisplayCurrency.current)) : Int(value).formatted()
    }

    private var fileName: String {
        "App Sales \(metric.title) by \(split.title.lowercased()) \(period) days"
    }

    /// Silver to grey, light at the bottom of each bar, so the largest group stands out.
    private static func shades(_ count: Int) -> [Color] {
        (0..<max(count, 1)).map { Color(white: 0.92 - 0.6 * Double($0) / Double(max(count - 1, 1))) }
    }
}
