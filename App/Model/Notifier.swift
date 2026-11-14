import BackgroundTasks
import Foundation
import UserNotifications

/// Local notifications without a server: iOS wakes the app now and then in the background, it asks Apple what's new
/// and tells the user about it. When iOS wakes it is up to iOS, so a notification can come a while after the event.
///
/// What was last seen (version states, review IDs, the newest report day) is kept, so each change is told once.
/// A refresh while the app is open updates what was seen without notifying: the user is looking anyway.
enum Notifier {
    enum Kind: String, CaseIterable {
        case status, reviews, summary, milestones

        var title: String {
            switch self {
            case .status: "Review status"
            case .reviews: "New reviews"
            case .summary: "Yesterday's numbers"
            case .milestones: "Milestones"
            }
        }

        var detail: String {
            switch self {
            case .status: "When a version goes into review, is approved or rejected."
            case .reviews: "When someone reviews one of your apps."
            case .summary: "In the morning, once Apple has the new day."
            case .milestones: "When an app reaches 10, 100, 1,000 … downloads."
            }
        }
    }

    static var taskID: String { (Bundle.main.bundleIdentifier ?? "studio.oxdeploy.appsales") + ".refresh" }
    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppGroup.id) }

    static func isOn(_ kind: Kind) -> Bool { defaults?.bool(forKey: "notify." + kind.rawValue) ?? false }

    static func set(_ kind: Kind, on: Bool) async -> Bool {
        if on {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return false }
            schedule()
        }
        defaults?.set(on, forKey: "notify." + kind.rawValue)
        return on
    }

    static var anyOn: Bool { Kind.allCases.contains(where: isOn) }

    // MARK: Background refresh

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            schedule()
            // iOS hands the task over once and waits for it to be completed.
            nonisolated(unsafe) let task = task
            let work = Task {
                await checkInBackground()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    /// Asks iOS for the next wake-up, at the earliest in an hour.
    static func schedule() {
        guard anyOn else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = .now.addingTimeInterval(3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func checkInBackground() async {
        guard !DemoData.isOn, let account = KeyStore.load(), let client = try? Client(key: account.key),
              let apps = try? await client.apps() else { return }
        var reviews: [Review] = []
        if isOn(.reviews) {
            for app in apps { reviews += (try? await client.reviews(appID: app.id, limit: 5)) ?? [] }
        }
        // The days of this month and the last, and the monthly reports on disk: enough for the milestones.
        let days = (try? await ReportCache.days(ReportDay.recent(62), client: client, vendor: account.vendorNumber)) ?? [:]
        let months = ReportDay.recentMonths(12).reduce(into: [String: [SalesRow]]()) { $0[$1] = MonthCache.load("months", $1) }
        await notice(Figures(apps: apps, days: days, rates: await Rates.current(), months: months), reviews: reviews, notify: true)
    }

    // MARK: Changes

    /// Compares with what was seen last and, when `notify`, tells about the changes.
    static func notice(_ figures: Figures, reviews: [Review], notify: Bool) async {
        var messages: [(kind: Kind, title: String, body: String)] = []

        var states = defaults?.dictionary(forKey: "seen.states") as? [String: String] ?? [:]
        for app in figures.apps {
            guard let version = app.versions.first else { continue }
            let now = "\(version.string) \(version.state)"
            if let before = states[app.id], before != now, let message = statusMessage(app: app, version: version) {
                messages.append((.status, message.title, message.body))
            }
            states[app.id] = now
        }
        defaults?.set(states, forKey: "seen.states")

        var seen = Set(defaults?.stringArray(forKey: "seen.reviews") ?? [])
        let fresh = reviews.filter { !seen.contains($0.id) }
        if !seen.isEmpty {
            for review in fresh.prefix(3) {
                let name = figures.apps.first { $0.id == review.appID }?.name ?? "Your app"
                messages.append((.reviews, "\(name) \(String(repeating: "★", count: review.rating))",
                                 review.title.isEmpty ? review.body : review.title))
            }
        }
        seen.formUnion(reviews.map(\.id))
        defaults?.set(Array(seen.suffix(500)), forKey: "seen.reviews")

        if let latest = figures.latestDay, latest != defaults?.string(forKey: "seen.day") {
            if defaults?.string(forKey: "seen.day") != nil {
                messages.append((.summary, "Yesterday", "\(figures.units(.download, days: 1)) downloads, \(figures.proceedsText(days: 1))"))
            }
            defaults?.set(latest, forKey: "seen.day")
        }

        var reached = defaults?.dictionary(forKey: "seen.milestones") as? [String: Int] ?? [:]
        for app in figures.apps {
            let downloads = figures.lifetimeDownloads(app: app)
            guard let milestone = Self.milestones.last(where: { $0 <= downloads }) else { continue }
            if let before = reached[app.id], milestone > before {
                messages.append((.milestones, app.name, "\(milestone.formatted()) downloads. Well done."))
            }
            reached[app.id] = max(milestone, reached[app.id] ?? 0)
        }
        defaults?.set(reached, forKey: "seen.milestones")

        guard notify else { return }
        for message in messages where isOn(message.kind) {
            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    private static let milestones = [10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000, 100_000, 250_000, 1_000_000]

    private static func statusMessage(app: StoreApp, version: StoreApp.Version) -> (title: String, body: String)? {
        let name = "\(app.name) \(version.string)"
        switch version.state {
        case "IN_REVIEW": return (name, "Apple is reviewing it now.")
        case "PENDING_DEVELOPER_RELEASE": return (name, "Approved. Release it in App Store Connect when you're ready.")
        case "READY_FOR_DISTRIBUTION": return (name, "It's in the App Store.")
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": return (name, "Rejected. Apple's message is in App Store Connect.")
        default: return nil
        }
    }
}
