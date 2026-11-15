import Foundation

/// One month for the books: what each app earned in which country, from Apple's monthly sales summary,
/// and what Apple's financial report says it owes for the month.
public struct Statement {
    public struct Line {
        public let app: String
        public let country: String
        public let downloads: Int
        public let purchases: Int
        public let refunds: Int
        /// In the currency Apple reports for the country.
        public let proceeds: Double
        public let currency: String
        /// In the display currency, at the ECB's rate.
        public let converted: Double
    }

    public let month: String
    public let currency: String
    public let lines: [Line]
    /// Apple's financial report, per currency. Empty until Apple publishes it, some days after the month.
    public let payout: [String: Double]
    public let payoutConverted: Double

    public var title: String { Self.title(month) }

    public static func title(_ month: String) -> String {
        ReportDay.date(month + "-01")?.formatted(.dateTime.month(.wide).year()) ?? month
    }

    public var total: Double { lines.reduce(0) { $0 + $1.converted } }

    /// Per app, largest first.
    public var apps: [(app: String, downloads: Int, purchases: Int, refunds: Int, converted: Double)] {
        Dictionary(grouping: lines, by: \.app).map { app, lines in
            (app, lines.reduce(0) { $0 + $1.downloads }, lines.reduce(0) { $0 + $1.purchases },
             lines.reduce(0) { $0 + $1.refunds }, lines.reduce(0) { $0 + $1.converted })
        }
        .sorted { ($0.converted, $0.downloads) > ($1.converted, $1.downloads) }
    }

    /// Proceeds per currency as Apple reports them, largest converted amount first.
    public var currencies: [(currency: String, proceeds: Double, converted: Double)] {
        Dictionary(grouping: lines.filter { !$0.currency.isEmpty }, by: \.currency).map { currency, lines in
            (currency, lines.reduce(0) { $0 + $1.proceeds }, lines.reduce(0) { $0 + $1.converted })
        }
        .sorted { $0.converted > $1.converted }
    }

    public func csv() -> String {
        var rows = [["App", "Country", "Country code", "Downloads", "In-app purchases", "Refunds", "Proceeds", "Currency",
                     "Proceeds (\(currency))"]]
        for line in lines {
            rows.append([line.app, Figures.countryName(line.country), line.country, "\(line.downloads)", "\(line.purchases)",
                         "\(line.refunds)", Figures.amount(line.proceeds), line.currency, Figures.amount(line.converted)])
        }
        return Figures.csv(rows)
    }
}

extension Figures {
    /// The months a statement can be made for: those Apple has a monthly sales summary of, newest first.
    public var statementMonths: [String] {
        months.filter { !$0.value.isEmpty }.keys.sorted(by: >)
    }

    public func statement(_ month: String) -> Statement {
        let currency = DisplayCurrency.current
        let rows = months[month] ?? []
        var lines: [Statement.Line] = []
        for app in apps {
            let byCountry = Dictionary(grouping: rows.filter { belongs($0, to: app) }) { $0.country + "\t" + $0.proceedsCurrency }
            for (key, rows) in byCountry {
                let parts = key.components(separatedBy: "\t")
                let downloads = rows.filter { $0.kind == .download && !$0.isRefund }.reduce(0) { $0 + $1.units }
                let purchases = rows.filter { $0.kind == .purchase && !$0.isRefund }.reduce(0) { $0 + $1.units }
                let refunds = -rows.filter(\.isRefund).reduce(0) { $0 + $1.units }
                let proceeds = rows.reduce(0) { $0 + $1.proceeds * Double($1.units) }
                guard downloads + purchases + refunds > 0 || proceeds != 0 else { continue }
                let converted = parts[1].isEmpty ? 0 : rates.total([parts[1]: proceeds], in: currency).total
                lines.append(.init(app: app.name, country: parts[0], downloads: downloads, purchases: purchases, refunds: refunds,
                                   proceeds: proceeds, currency: parts[1], converted: converted))
            }
        }
        lines.sort { ($0.app, -$0.converted, -$0.downloads, $0.country) < ($1.app, -$1.converted, -$1.downloads, $1.country) }
        let payout = (payouts[month] ?? []).reduce(into: [String: Double]()) { $0[$1.currency, default: 0] += $1.amount }
        return Statement(month: month, currency: currency, lines: lines, payout: payout,
                         payoutConverted: rates.total(payout, in: currency).total)
    }
}
