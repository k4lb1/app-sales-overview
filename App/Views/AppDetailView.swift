import Charts
import SwiftUI

struct AppDetailView: View {
    @Environment(Dashboard.self) private var dashboard
    let app: StoreApp

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    AppIcon(app: app, url: dashboard.icons[app.id], size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name).font(.title3.weight(.semibold))
                        ForEach(app.versions.prefix(2), id: \.self) { StatePill(version: $0) }
                    }
                }

                HStack(spacing: 12) {
                    figure("Downloads", "\(dashboard.figures.units(.download, days: 30, app: app))")
                    figure("Updates", "\(dashboard.figures.units(.update, days: 30, app: app))")
                }
                figure("Proceeds", dashboard.figures.proceedsText(days: 30, app: app))
                if !dashboard.figures.discovery.isEmpty {
                    HStack(spacing: 12) {
                        figure("Impressions", "\(dashboard.figures.impressions(days: 30, app: app))")
                        figure("Page views", "\(dashboard.figures.pageViews(days: 30, app: app))")
                    }
                }

                Chart(dashboard.figures.downloadsPerDay(30, app: app), id: \.day) { point in
                    BarMark(x: .value("Day", point.day, unit: .day), y: .value("Downloads", point.units))
                        .foregroundStyle(Color.sales)
                        .cornerRadius(3)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 160)
                .card()

                let countries = dashboard.figures.countries(days: 30, app: app)
                if !countries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Countries").font(.headline)
                        ForEach(countries, id: \.country) { entry in
                            HStack {
                                Text(Locale.current.localizedString(forRegionCode: entry.country) ?? entry.country)
                                Spacer()
                                Text("\(entry.units)").monospacedDigit().foregroundStyle(Color.muted)
                            }
                        }
                    }
                    .card()
                }

                Text("Last 30 days. Bundle ID \(app.bundleID)").font(.caption).foregroundStyle(Color.muted)
            }
            .padding(16)
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func figure(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Color.muted)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .card()
    }
}
