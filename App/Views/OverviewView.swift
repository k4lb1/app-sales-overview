import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(Dashboard.self) private var dashboard
    @State private var period = 7
    @State private var showsStatement = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $period) {
                    Text("Yesterday").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .pickerStyle(.segmented)

                totals
                if period > 1 { chart }
                appList
                subscriptions
                months
                payouts

                if let error = dashboard.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                footnote
            }
            .padding(16)
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ExportMenu(days: period) }
        }
        .refreshable { await dashboard.refresh() }
        .sheet(isPresented: $showsStatement) { StatementView() }
        .overlay {
            if dashboard.isLoading && dashboard.figures.apps.isEmpty { ProgressView() }
        }
    }

    private var totals: some View {
        let figures = dashboard.figures
        let downloads = figures.units(.download, days: period)
        let proceeds = figures.proceedsTotal(days: period)
        let refunds = figures.refunds(days: period)
        return HStack(spacing: 12) {
            figure("Downloads", "\(downloads)",
                   change: figures.change(Double(downloads), Double(figures.units(.download, days: period, previous: true)), days: period))
            figure("Proceeds", figures.proceedsText(days: period),
                   change: figures.change(proceeds, figures.proceedsTotal(days: period, previous: true), days: period),
                   note: refunds > 0 ? "\(refunds) refunded" : nil)
        }
    }

    private func figure(_ title: LocalizedStringKey, _ value: String, change: Double?, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.muted)
            Text(value).font(.title.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            HStack(spacing: 6) {
                if let change { ChangeLabel(change: change, period: period) }
                if let note { Text(note).foregroundStyle(Color.muted) }
            }
            .font(.caption)
        }
        .card()
    }

    private var chart: some View {
        let points = dashboard.figures.downloadsPerDay(period)
        return Chart {
            ForEach(points, id: \.day) { point in
                BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.units))
                    .foregroundStyle(Color.sales)
                    .cornerRadius(period > 30 ? 1 : 3)
            }
            ReleaseMarks(releases: dashboard.figures.releases(), from: points.first?.day)
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .frame(height: 140)
        .card()
    }

    private var appList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apps").font(.headline)
            ForEach(dashboard.figures.apps.sorted { dashboard.figures.units(.download, days: period, app: $0) > dashboard.figures.units(.download, days: period, app: $1) }) { app in
                NavigationLink(value: app) {
                    HStack(spacing: 12) {
                        AppIcon(app: app, url: dashboard.icons[app.id])
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.body.weight(.medium)).lineLimit(1)
                            Text(app.live.map { "\($0.string)" } ?? String(localized: "Not in the store yet"))
                                .font(.caption).foregroundStyle(Color.muted)
                        }
                        Spacer(minLength: 8)
                        Text("\(dashboard.figures.units(.download, days: period, app: app))").font(.body.weight(.semibold)).monospacedDigit()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    /// Only when the account sells subscriptions.
    @ViewBuilder
    private var subscriptions: some View {
        let figures = dashboard.figures
        if !figures.subscriptions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Subscriptions").font(.headline)
                HStack(spacing: 0) {
                    stat("Active", "\(figures.activeSubscriptions())")
                    stat("In trial", "\(figures.trials())")
                    stat("Per month", figures.monthlyRecurring().formatted(.currency(code: DisplayCurrency.current).precision(.fractionLength(0))))
                }
                Text("Active subscriptions as of Apple's newest report. Per month: what the paid ones bring in at their standard price.")
                    .font(.caption).foregroundStyle(Color.muted)
            }
            .card()
        }
    }

    @ViewBuilder
    private var months: some View {
        let monthly = dashboard.figures.monthly()
        if !monthly.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 12 months").font(.headline)
                Chart(monthly, id: \.month) { point in
                    BarMark(x: .value("Month", point.month, unit: .month), y: .value("Downloads", point.downloads))
                        .foregroundStyle(Color.sales)
                        .cornerRadius(3)
                }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 140)
                let total = monthly.reduce(0) { $0 + $1.proceeds }
                Text("\(monthly.reduce(0) { $0 + $1.downloads }) downloads · \(total.formatted(.currency(code: DisplayCurrency.current)))")
                    .font(.caption).foregroundStyle(Color.muted)
                Button("Monthly statement", systemImage: "doc.text") { showsStatement = true }
                    .font(.callout)
            }
            .card()
        }
    }

    /// Apple's financial reports: what each month earned, and when it's paid.
    @ViewBuilder
    private var payouts: some View {
        let months = dashboard.figures.payoutMonths().filter { $0.amount != 0 }
        if !months.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Payouts").font(.headline)
                ForEach(months.prefix(6), id: \.month) { month in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(month.month.formatted(.dateTime.month(.wide).year()))
                            Text(month.expected > .now
                                 ? "Expected around \(month.expected.formatted(.dateTime.day().month(.abbreviated)))"
                                 : "Paid")
                                .font(.caption).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Text(month.amount.formatted(.currency(code: DisplayCurrency.current))).monospacedDigit()
                    }
                }
                Text("From Apple's financial reports, converted at the ECB's rate. Apple pays within 33 days of a month's end, at its own rate, after taxes it withholds.")
                    .font(.caption).foregroundStyle(Color.muted)
            }
            .card()
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(Color.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footnote: some View {
        if let latest = dashboard.figures.latestDay, let date = ReportDay.date(latest) {
            Text("Apple's newest report: \(date.formatted(.dateTime.day().month(.wide))). Each day's report arrives the next morning, Pacific time.")
                .font(.caption).foregroundStyle(Color.muted)
        }
    }
}

/// "▲ 18 %" against the period before.
struct ChangeLabel: View {
    let change: Double
    let period: Int

    var body: some View {
        let up = change >= 0
        Text("\(up ? "▲" : "▼") \(abs(change).formatted(.percent.precision(.fractionLength(0))))")
            .foregroundStyle(up ? Color.green : Color.red)
            .accessibilityLabel("\(up ? "Up" : "Down") \(abs(change).formatted(.percent.precision(.fractionLength(0)))) on the \(period == 1 ? "day" : "\(period) days") before")
    }
}

/// A dashed line on the day a version went live, labelled with it, to see what an update did.
struct ReleaseMarks: ChartContent {
    let releases: [(app: StoreApp, version: String, day: Date)]
    /// The chart's first day; earlier releases are left out.
    let from: Date?
    var showsApp = true

    var body: some ChartContent {
        let visible = releases.filter { release in from.map { release.day >= $0 } ?? false }
        ForEach(visible.indices, id: \.self) { index in
            let release = visible[index]
            RuleMark(x: .value("Release", release.day, unit: .day))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.white.opacity(0.45))
                .annotation(position: .top, alignment: .leading, spacing: 2,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    Text(showsApp ? "\(Self.short(release.app.name)) \(release.version)" : release.version)
                        .font(.system(size: 9)).foregroundStyle(Color.muted)
                }
        }
    }

    /// "Tideline – Tide Tables" → "Tideline".
    private static func short(_ name: String) -> String {
        name.components(separatedBy: " – ").first?.components(separatedBy: " - ").first ?? name
    }
}
