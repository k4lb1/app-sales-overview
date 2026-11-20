import SwiftUI

struct StoreView: View {
    @Environment(Dashboard.self) private var dashboard
    @State private var period = 7

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                discovery
                atApple
                reviews
            }
            .padding(16)
        }
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle("Store")
        .refreshable { await dashboard.refresh() }
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovery").font(.headline)
                Spacer()
                Picker("Period", selection: $period) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            let figures = dashboard.figures
            if figures.discovery.isEmpty {
                Text(dashboard.analyticsError ?? String(localized: "Apple is preparing the first store analytics. They usually arrive one to two days after the first launch."))
                    .font(.callout).foregroundStyle(Color.muted)
            } else {
                HStack(spacing: 8) {
                    step("Impressions", figures.impressions(days: period).formatted())
                    step("Page views", figures.pageViews(days: period).formatted())
                    step("Downloads", figures.units(.download, days: period).formatted())
                    step("Conversion", figures.conversion(days: period).map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "–")
                }
                let sources = figures.sources(days: period)
                if !sources.isEmpty {
                    Divider().overlay(Color.card)
                    ForEach(sources, id: \.source) { entry in
                        HStack {
                            Text(entry.source).font(.callout)
                            Spacer()
                            Text("\(entry.counts)").monospacedDigit().foregroundStyle(Color.muted)
                        }
                    }
                }
                Text("Store analytics arrive a day or two after the sales.").font(.caption).foregroundStyle(Color.muted)
            }
        }
        .card()
    }

    private func step(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var atApple: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("At Apple").font(.headline)
            let pending = dashboard.figures.pending
            if pending.isEmpty {
                Text("Every app is in the store with its newest version.").font(.callout).foregroundStyle(Color.muted)
            }
            ForEach(pending) { app in
                HStack(spacing: 12) {
                    AppIcon(app: app, url: dashboard.icons[app.id], size: 32)
                    Text(app.name).lineLimit(1)
                    Spacer(minLength: 8)
                    StatePill(version: app.pending!)
                }
            }
        }
        .card()
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reviews").font(.headline)
            if dashboard.reviews.isEmpty {
                Text("No reviews yet. New ones from every app show up here.").font(.callout).foregroundStyle(Color.muted)
            }
            ForEach(dashboard.reviews) { review in
                ReviewRow(review: review, app: dashboard.figures.apps.first { $0.id == review.appID },
                          icon: dashboard.icons[review.appID])
                if review.id != dashboard.reviews.last?.id { Divider().overlay(Color.card) }
            }
        }
        .card()
    }
}

struct ReviewRow: View {
    let review: Review
    let app: StoreApp?
    let icon: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let app { AppIcon(app: app, url: icon, size: 22) }
                Text(String(repeating: "★", count: review.rating) + String(repeating: "☆", count: max(0, 5 - review.rating)))
                    .foregroundStyle(Color.sales)
                Spacer()
                Text(review.date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(Color.muted)
            }
            if !review.title.isEmpty { Text(review.title).font(.body.weight(.semibold)) }
            if !review.body.isEmpty { Text(review.body).font(.callout) }
            // Apple names the storefront with three letters, e.g. DEU or USA.
            Text("\(review.nickname) · \(review.territory)")
                .font(.caption).foregroundStyle(Color.muted)
        }
    }
}
