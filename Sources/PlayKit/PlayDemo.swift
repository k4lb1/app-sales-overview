import ASCKit
import Foundation

/// Example Android apps and figures for the demo, in the shape the reports have, so every Google Play tile and sensor
/// can be tried without an account.
public enum PlayDemo {
    public static func figures(now: Date = .now) -> PlayFigures {
        let apps = [PlayApp(id: "com.example.tideline", name: "Tideline – Tide Tables"),
                    PlayApp(id: "com.example.moss", name: "Moss – Habit Garden"),
                    PlayApp(id: "com.example.kiln", name: "Kiln Timer")]
        let base = ["com.example.tideline": 140.0, "com.example.moss": 90.0, "com.example.kiln": 25.0]
        let prices = ["com.example.tideline": 2.99, "com.example.moss": 3.99, "com.example.kiln": 1.99]
        let countries = ["DE": 0.3, "US": 0.25, "IN": 0.2, "BR": 0.15, "GB": 0.1]
        var generator = SystemRandomNumberGenerator()
        var figures = PlayFigures(apps: apps)
        for day in ReportDay.recent(60, from: now) {
            let weekday = Calendar(identifier: .gregorian).component(.weekday, from: ReportDay.date(day) ?? now)
            for app in apps {
                let installs = Int(base[app.id]! * (weekday == 1 || weekday == 7 ? 1.25 : 1) * Double.random(in: 0.8...1.2, using: &generator))
                figures.installs.append(PlayInstallRow(day: day, package: app.id, installs: installs, uninstalls: installs / 3))
                for (country, share) in countries {
                    figures.countries.append(PlayInstallRow(day: day, package: app.id, country: country,
                                                            installs: Int(Double(installs) * share), uninstalls: 0))
                }
                for _ in 0..<max(1, installs / 30) {
                    figures.sales.append(PlaySaleRow(day: day, package: app.id, country: countries.keys.randomElement(using: &generator)!,
                                                     currency: "EUR", amount: prices[app.id]!, isRefund: false))
                }
                if Int.random(in: 0..<25, using: &generator) == 0 {
                    figures.sales.append(PlaySaleRow(day: day, package: app.id, country: "DE", currency: "EUR", amount: -prices[app.id]!, isRefund: true))
                }
            }
        }
        let texts = [(5, "Exactly what I needed, clean and fast."), (4, "Great, but please add a widget."),
                     (2, "Crashes when I rotate the phone."), (5, "Lovely little app.")]
        for (index, text) in texts.enumerated() {
            let app = apps[index % apps.count]
            figures.reviews.append(PlayReview(id: "demo-\(index)", package: app.id, rating: text.0, text: text.1, author: "Demo",
                                              date: now.addingTimeInterval(-Double(index) * 86_400 * 1.5)))
        }
        // The earnings: a month's charges with Google's 15 % fee, in euros, for the months that are over.
        for sale in figures.sales {
            let month = String(sale.day.prefix(7))
            guard month < String(ReportDay.recent(1, from: now).first?.prefix(7) ?? "") else { continue }
            let kind: PlayEarningRow.Kind = sale.isRefund ? .refund : .charge
            figures.earnings.append(PlayEarningRow(month: month, date: sale.day, kind: kind, type: sale.isRefund ? "Charge refund" : "Charge",
                                                   package: sale.package, country: sale.country, amount: sale.amount, currency: "EUR"))
            figures.earnings.append(PlayEarningRow(month: month, date: sale.day, kind: .fee, type: sale.isRefund ? "Google fee refund" : "Google fee",
                                                   package: sale.package, country: sale.country, amount: -sale.amount * 0.15, currency: "EUR"))
        }
        for app in apps {
            figures.crashes[app.id] = ReportDay.recent(30, from: now.addingTimeInterval(-2 * 86_400)).map { day in
                let rate = app.id == "com.example.kiln" ? 0.012 : 0.003
                return PlayCrashDay(day: day, crashRate: rate * Double.random(in: 0.7...1.3, using: &generator), userPerceived: rate * 0.6)
            }
        }
        return figures
    }
}
