import SwiftUI

/// What the app does and how, shown once at first launch and again from Settings.
struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    Image("Mark").resizable().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 14, style: .continuous))
                    Text("All your apps at a glance").font(.largeTitle.weight(.semibold))
                    Text("App Sales Overview reads your figures straight from App Store Connect and puts every app on one screen.")
                        .foregroundStyle(Color.muted)
                }
                VStack(alignment: .leading, spacing: 22) {
                    step("chart.bar.xaxis", "Overview",
                         "Downloads and proceeds of yesterday, the last 7 or 30 days, over all apps and per app. Export them as CSV.")
                    step("bag", "Store",
                         "How often your apps are seen and opened in the App Store, what's waiting for review, and new reviews.")
                    step("rectangle.grid.2x2", "Widgets",
                         "Yesterday's downloads on your Home Screen and Lock Screen, updated on their own.")
                    step("key", "Your own key, nothing else",
                         "You connect an App Store Connect API key once. It stays in this iPhone's Keychain and only ever goes to Apple. There is no server.")
                    step("clock", "Apple's timing",
                         "Each day's sales arrive the next morning. Store analytics follow a day or two later, the first ones one to two days after you connect.")
                }
            }
            .padding(24)
            .padding(.bottom, 80)
        }
        .background(Color.ground)
        .overlay(alignment: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Get started").font(.body.weight(.semibold)).foregroundStyle(Color.ground)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.sales).interactive(), in: .capsule)
            .padding(24)
        }
        .foregroundStyle(Color.ink)
    }

    private func step(_ symbol: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.sales).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.callout).foregroundStyle(Color.muted)
            }
        }
    }
}
