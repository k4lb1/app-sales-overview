import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(Dashboard.self) private var dashboard
    @State private var period = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $period) {
                    Text("Yesterday").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                totals
                if period > 1 { chart }
                appList

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
        .overlay {
            if dashboard.isLoading && dashboard.figures.apps.isEmpty { ProgressView() }
        }
    }

    private var totals: some View {
        HStack(spacing: 12) {
            figure("Downloads", "\(dashboard.figures.units(.download, days: period))")
            figure("Proceeds", dashboard.figures.proceedsText(days: period))
        }
    }

    private func figure(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.muted)
            Text(value).font(.title.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .card()
    }

    private var chart: some View {
        Chart(dashboard.figures.downloadsPerDay(period), id: \.day) { point in
            BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.units))
                .foregroundStyle(Color.sales)
                .cornerRadius(3)
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

    @ViewBuilder
    private var footnote: some View {
        if let latest = dashboard.figures.latestDay, let date = ReportDay.date(latest) {
            Text("Apple's newest report: \(date.formatted(.dateTime.day().month(.wide))). Each day's report arrives the next morning, Pacific time.")
                .font(.caption).foregroundStyle(Color.muted)
        }
    }
}
