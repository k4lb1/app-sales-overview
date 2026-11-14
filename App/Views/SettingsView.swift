import SwiftUI

struct SettingsView: View {
    @Environment(Dashboard.self) private var dashboard
    @State private var currency = DisplayCurrency.current
    @State private var confirmsRemoval = false
    @AppStorage("welcomeSeen") private var welcomeSeen = true
    @State private var notifications = Dictionary(uniqueKeysWithValues: Notifier.Kind.allCases.map { ($0, Notifier.isOn($0)) })
    @State private var notificationsDenied = false

    private static let version: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }()

    var body: some View {
        Form {
            Section {
                Picker("Currency", selection: $currency) {
                    ForEach(DisplayCurrency.choices, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
            } header: {
                Text("Proceeds")
            } footer: {
                Text("Apple pays each country in its own currency. The totals are converted with the European Central Bank's daily rates.")
            }

            Section {
                ForEach(Notifier.Kind.allCases, id: \.self) { kind in
                    Toggle(isOn: Binding(get: { notifications[kind] ?? false }, set: { on in
                        notifications[kind] = on
                        Task {
                            let result = await Notifier.set(kind, on: on)
                            notifications[kind] = result
                            notificationsDenied = on && !result
                        }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                            Text(kind.detail).font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text(notificationsDenied
                     ? "Notifications are off for App Sales in the iPhone's Settings."
                     : "Checked in the background when iOS allows it, so a notification can come a little later.")
            }

            if dashboard.isDemo {
                Section {
                    Button("Leave sample data", role: .destructive) { dashboard.stopDemo() }
                } header: {
                    Text("Sample data")
                } footer: {
                    Text("The apps and figures shown are invented. Leave to connect your own key.")
                }
            } else if let account = dashboard.account {
                Section {
                    LabeledContent("Issuer ID", value: String(account.issuer.prefix(8)) + "…")
                    LabeledContent("Key ID", value: account.keyID)
                    LabeledContent("Vendor number", value: account.vendorNumber)
                    Button("Remove key", role: .destructive) { confirmsRemoval = true }
                } header: {
                    Text("App Store Connect")
                } footer: {
                    Text("The key is kept in this iPhone's Keychain and is only ever sent to Apple.")
                }
            }

            Section("About") {
                // Shown by the app's top-level sheet: one presented from a form row closes again on the first tap.
                Button("How it works") { welcomeSeen = false }
                LabeledContent("Version", value: Self.version)
                Link(destination: URL(string: "https://github.com/k4lb1/app-sales-overview")!) {
                    LabeledContent("Open Source") {
                        Text("GitHub").foregroundStyle(Color.sales)
                    }
                }
                LabeledContent("Made by", value: "0xdeploy.studio")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ground.ignoresSafeArea())
        .navigationTitle("Settings")
        .onChange(of: currency) { _, code in
            DisplayCurrency.set(code)
            dashboard.currencyChanged()
        }
        .confirmationDialog("Remove the key?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { dashboard.disconnect() }
        } message: {
            Text("The key and the stored reports are deleted from this iPhone. The key itself stays valid in App Store Connect.")
        }
    }
}
