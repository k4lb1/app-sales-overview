import SwiftUI

@main
struct AppSalesApp: App {
    @State private var dashboard = Dashboard()
    @AppStorage("welcomeSeen") private var welcomeSeen = false

    init() {
        Notifier.register()
    }
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if dashboard.isSetUp {
                    RootView()
                } else {
                    NavigationStack { SetupView() }
                }
            }
            .environment(dashboard)
            .preferredColorScheme(.dark)
            .tint(Color.sales)
            .sheet(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) { WelcomeView() }
            .task { await dashboard.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await dashboard.refresh() } }
                if phase == .background { Notifier.schedule() }
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Overview", systemImage: "chart.bar.xaxis") {
                NavigationStack {
                    OverviewView().navigationDestination(for: StoreApp.self) { AppDetailView(app: $0) }
                }
            }
            Tab("Store", systemImage: "bag") {
                NavigationStack { StoreView() }
            }
            Tab("Settings", systemImage: "slider.horizontal.3") {
                NavigationStack { SettingsView() }
            }
        }
    }
}
