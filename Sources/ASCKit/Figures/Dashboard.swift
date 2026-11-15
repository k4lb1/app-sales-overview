import Foundation
import Observation
import WidgetKit

@MainActor @Observable
public final class Dashboard {
    /// The longest period is 90 days, compared with the 90 before.
    public static let maxDays = 180

    private(set) var account: Account?
    private(set) var figures = Figures()
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var icons: [String: URL] = [:]
    private(set) var reviews: [Review] = []
    /// Why there are no analytics, when Apple refused them (a key without the Admin role).
    private(set) var analyticsError: String?
    /// Runs after each refresh with fresh numbers: the iPhone app notifies from here, the Mac app checks its sensors.
    public var afterRefresh: (@MainActor (Figures, [Review]) async -> Void)?

    public init() {
        account = KeyStore.load()
        let saved = UserDefaults(suiteName: AppGroup.id)?.dictionary(forKey: "icons") as? [String: String] ?? [:]
        icons = saved.compactMapValues(URL.init(string:))
        if account != nil { figures.apps = ReportCache.loadApps() }
    }

    public var isSetUp: Bool { account != nil || isDemo }
    private(set) var isDemo = DemoData.isOn

    public func startDemo() {
        DemoData.isOn = true
        isDemo = true
        Task { await refresh() }
    }

    public func stopDemo() {
        DemoData.isOn = false
        isDemo = false
        figures = Figures()
        reviews = []
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func connect(_ account: Account) async throws {
        // Checks the key before keeping it: a wrong key or ID fails here, with Apple's message.
        _ = try await Client(key: account.key).apps()
        if self.account != account { ReportCache.clear() }
        if isDemo { stopDemo() }
        KeyStore.save(account)
        self.account = account
        figures = Figures()
        await refresh()
    }

    public func disconnect() {
        KeyStore.delete()
        ReportCache.clear()
        account = nil
        figures = Figures()
        icons = [:]
        UserDefaults(suiteName: AppGroup.id)?.removeObject(forKey: "icons")
        reviews = []
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func refresh() async {
        if isDemo {
            figures = DemoData.figures()
            figures.rates = await Rates.current()
            reviews = DemoData.reviews()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        guard let account, !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let client = try Client(key: account.key)
            let apps = try await client.apps()
            ReportCache.saveApps(apps)
            figures.apps = apps
            figures.days = try await ReportCache.days(ReportDay.recent(Self.maxDays), client: client, vendor: account.vendorNumber)
            figures.rates = await Rates.current()
            WidgetCenter.shared.reloadAllTimelines()
            await loadMoney(client: client, vendor: account.vendorNumber)
            await loadIcons()
            await loadReviews(client: client)
            await loadDiscovery(client: client)
            await afterRefresh?(figures, reviews)
        } catch {
            self.error = String(describing: error)
        }
    }

    /// The last 12 months of sales and of Apple's financial reports, and the active subscriptions.
    private func loadMoney(client: Client, vendor: String) async {
        let months = ReportDay.recentMonths(12)
        figures.months = await MonthCache.months("months", months) { try await client.salesReport(vendor: vendor, month: $0) }
        figures.payouts = await MonthCache.months("payouts", months) { try await client.financeReport(vendor: vendor, month: $0) }
        for day in ReportDay.recent(3) {
            if let rows = try? await client.subscriptionReport(vendor: vendor, day: day) {
                figures.subscriptions = rows
                break
            }
        }
    }

    private func loadReviews(client: Client) async {
        var all: [Review] = []
        for app in figures.apps {
            all += (try? await client.reviews(appID: app.id)) ?? []
        }
        reviews = all.sorted { $0.date > $1.date }
    }

    private func loadDiscovery(client: Client) async {
        do {
            figures.discovery = try await AnalyticsCache.discovery(apps: figures.apps, days: Self.maxDays, client: client)
            analyticsError = nil
        } catch ASCError.http(403, _) {
            analyticsError = String(localized: "Store analytics need a key with the Admin role.")
        } catch {
            analyticsError = String(describing: error)
        }
    }

    public func currencyChanged() {
        // The figures read the currency when they're shown; touching them redraws what shows an amount.
        figures.rates = figures.rates
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Icon URLs are kept, so they show right away on the next launch.
    private func loadIcons() async {
        let region = Locale.current.region?.identifier.lowercased() ?? "us"
        let storefronts = [region] + ["us", "de", "gb", "fr", "jp"].filter { $0 != region }
        for app in figures.apps where icons[app.id] == nil && app.live != nil {
            if let url = await Client.iconURL(appID: app.id, storefronts: storefronts) { icons[app.id] = url }
        }
        UserDefaults(suiteName: AppGroup.id)?.set(icons.mapValues(\.absoluteString), forKey: "icons")
    }
}
