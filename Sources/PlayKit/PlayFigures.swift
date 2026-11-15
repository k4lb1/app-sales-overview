import ASCKit
import Foundation
import Security

/// Everything read from Google Play, and what's worked out of it, in the style of `Figures`: periods are counted back
/// from the newest day the reports have.
public struct PlayFigures: Sendable {
    public var apps: [PlayApp] = []
    /// One row per day and app.
    public var installs: [PlayInstallRow] = []
    /// One row per day, app and country.
    public var countries: [PlayInstallRow] = []
    public var sales: [PlaySaleRow] = []
    public var reviews: [PlayReview] = []
    /// Package → crash rate per day.
    public var crashes: [String: [PlayCrashDay]] = [:]
    /// Google's monthly earnings: every booking in the payout currency, for the books.
    public var earnings: [PlayEarningRow] = []

    /// What's left of a price after Google's service fee (15 % on the first million a year). An estimate: the exact
    /// payout is in Google's monthly earnings report.
    public static let afterFee = 0.85

    public init(apps: [PlayApp] = [], installs: [PlayInstallRow] = [], countries: [PlayInstallRow] = [], sales: [PlaySaleRow] = [],
                reviews: [PlayReview] = [], crashes: [String: [PlayCrashDay]] = [:], earnings: [PlayEarningRow] = []) {
        self.apps = apps
        self.installs = installs
        self.countries = countries
        self.sales = sales
        self.reviews = reviews
        self.crashes = crashes
        self.earnings = earnings
    }

    public var latestDay: String? { installs.map(\.day).max() }

    /// `count` reported days, newest first; `previous` takes the `count` days before those.
    public func reportedDays(_ count: Int, previous: Bool = false) -> [String] {
        Array(Set(installs.map(\.day)).sorted(by: >).dropFirst(previous ? count : 0).prefix(count))
    }

    public func installs(days count: Int, app: PlayApp? = nil, previous: Bool = false) -> Int {
        let days = Set(reportedDays(count, previous: previous))
        return installs.filter { days.contains($0.day) && (app == nil || $0.package == app!.id) }.reduce(0) { $0 + $1.installs }
    }

    public func installsPerDay(_ count: Int, app: PlayApp? = nil) -> [(day: Date, units: Int)] {
        reportedDays(count).reversed().compactMap { day in
            guard let date = ReportDay.date(day) else { return nil }
            return (date, installs.filter { $0.day == day && (app == nil || $0.package == app!.id) }.reduce(0) { $0 + $1.installs })
        }
    }

    /// Proceeds per currency after Google's fee, refunds taken off.
    public func proceeds(days count: Int, app: PlayApp? = nil, previous: Bool = false) -> [String: Double] {
        let days = Set(reportedDays(count, previous: previous))
        return sales.filter { days.contains($0.day) && (app == nil || $0.package == app!.id) }
            .reduce(into: [:]) { $0[$1.currency, default: 0] += $1.amount * Self.afterFee }
    }

    public func refunds(days count: Int, app: PlayApp? = nil) -> Int {
        let days = Set(reportedDays(count))
        return sales.filter { $0.isRefund && days.contains($0.day) && (app == nil || $0.package == app!.id) }.count
    }

    /// Installs per country over the period, largest first.
    public func countries(days count: Int, app: PlayApp? = nil) -> [(country: String, installs: Int)] {
        let days = Set(reportedDays(count))
        return Dictionary(grouping: countries.filter { days.contains($0.day) && (app == nil || $0.package == app!.id) }) { $0.country ?? "" }
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.installs }) }
            .sorted { $0.1 > $1.1 }
    }

    /// After answering a review, so the list is right without loading everything again.
    public mutating func setReply(_ text: String, forReview id: String) {
        guard let index = reviews.firstIndex(where: { $0.id == id }) else { return }
        reviews[index].reply = text
        reviews[index].replyDate = .now
    }

    /// Installs and proceeds (after Google's fee) per month ("yyyy-MM"), from the daily reports.
    public func monthly(app: PlayApp? = nil) -> [String: (installs: Int, proceeds: [String: Double])] {
        var months: [String: (installs: Int, proceeds: [String: Double])] = [:]
        for row in installs where app == nil || row.package == app!.id {
            months[String(row.day.prefix(7)), default: (0, [:])].installs += row.installs
        }
        for row in sales where app == nil || row.package == app!.id {
            months[String(row.day.prefix(7)), default: (0, [:])].proceeds[row.currency, default: 0] += row.amount * Self.afterFee
        }
        return months
    }

    /// The newest day's crash rate.
    public func crashRate(app: PlayApp) -> PlayCrashDay? {
        crashes[app.id]?.max { $0.day < $1.day }
    }
}

/// The Google side of the account: the service account's JSON key and the bucket the reports are in. Kept in the
/// Keychain, only on this device, like the App Store Connect key.
public struct PlayAccount: Codable, Equatable, Sendable {
    public var serviceAccountJSON: String
    /// "pubsite_prod_…", without "gs://" or a path.
    public var bucket: String

    public init(serviceAccountJSON: String, bucket: String) {
        self.serviceAccountJSON = serviceAccountJSON
        self.bucket = Self.bucket(from: bucket)
    }

    public var serviceAccount: ServiceAccount {
        get throws { try ServiceAccount(json: Data(serviceAccountJSON.utf8)) }
    }

    /// What the Play Console shows as the Cloud Storage URI ("gs://pubsite_prod_rev_0123/stats/…"), reduced to the bucket.
    public static func bucket(from text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("gs://") { name = String(name.dropFirst(5)) }
        return String(name.split(separator: "/").first ?? "")
    }
}

public enum PlayKeyStore {
    public static let service = "studio.oxdeploy.play.account"

    public static func load() -> PlayAccount? {
        Keychain.load(service).flatMap { try? JSONDecoder().decode(PlayAccount.self, from: $0) }
    }

    public static func save(_ account: PlayAccount, inICloud: Bool = false) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        Keychain.save(data, service: service, inICloud: inICloud)
    }

    public static func delete() { Keychain.delete(service) }
}

/// Reads the reports with a cache on disk: a month that's over doesn't change any more, so only this month and the
/// one before are fetched again. Files Google hasn't made (an app without installs that month) are skipped.
public enum PlayData {
    public static func load(_ account: PlayAccount, months count: Int = 7, now: Date = .now) async throws -> PlayFigures {
        let client = try PlayClient(account: try account.serviceAccount)
        var figures = PlayFigures(apps: try await client.apps())
        // This month first: Google writes its files during the month, and the newest days are in them.
        let running = String(ReportDay.string(now).prefix(7))
        let months = ([running] + ReportDay.recentMonths(count - 1, from: now)).map { $0.replacingOccurrences(of: "-", with: "") }
        let fresh = Set(months.sorted(by: >).prefix(2))
        func file(_ name: String) async -> Data? {
            if !fresh.contains(where: { name.contains($0) }), let cached = try? Data(contentsOf: folder.appending(path: cacheName(name))) {
                return cached
            }
            guard let data = try? await client.file(bucket: account.bucket, name: name) else { return nil }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appending(path: cacheName(name)), options: .atomic)
            return data
        }
        for app in figures.apps {
            for month in months {
                if let data = await file("stats/installs/installs_\(app.id)_\(month)_overview.csv") {
                    figures.installs += PlayReports.installs(data)
                }
                if let data = await file("stats/installs/installs_\(app.id)_\(month)_country.csv") {
                    figures.countries += PlayReports.installs(data)
                }
            }
            figures.reviews += (try? await client.reviews(package: app.id)) ?? []
            figures.crashes[app.id] = try? await client.crashRates(package: app.id, days: 30, now: now)
        }
        for month in months {
            if let data = await file("sales/salesreport_\(month).zip") { figures.sales += PlayReports.sales(data) }
            // The earnings report has the account's number and a part number in its name, so it's looked up.
            for name in (try? await client.files(bucket: account.bucket, prefix: "earnings/earnings_\(month)")) ?? [] where name.hasSuffix(".zip") {
                if let data = await file(name) {
                    figures.earnings += PlayReports.earnings(data, month: "\(month.prefix(4))-\(month.suffix(2))")
                }
            }
        }
        figures.reviews.sort { $0.date > $1.date }
        return figures
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: folder)
    }

    private static var folder: URL { AppGroup.folder.appending(path: "Play") }

    private static func cacheName(_ name: String) -> String { name.replacingOccurrences(of: "/", with: "_") }
}
