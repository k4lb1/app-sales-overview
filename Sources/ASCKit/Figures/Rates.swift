import Foundation

/// Apple pays each country's sales in its own currency. To show one total, the proceeds are converted with the
/// European Central Bank's daily reference rates: a public file, fetched without anything about the user.
struct Rates: Codable {
    /// Units of each currency per euro, as the ECB publishes them.
    var perEuro: [String: Double] = ["EUR": 1]
    var fetched: Date = .distantPast

    static let source = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    private static var file: URL { AppGroup.folder.appending(path: "rates.json") }

    static func cached() -> Rates {
        guard let data = try? Data(contentsOf: file), let rates = try? JSONDecoder().decode(Rates.self, from: data) else { return Rates() }
        return rates
    }

    /// Today's rates; the cached ones while they're younger than 12 hours or when the ECB can't be reached.
    static func current() async -> Rates {
        let cached = cached()
        guard cached.fetched < .now.addingTimeInterval(-12 * 3600),
              let (data, _) = try? await URLSession.shared.data(from: source) else { return cached }
        let xml = String(decoding: data, as: UTF8.self)
        var rates = Rates(fetched: .now)
        // Lines like <Cube currency='USD' rate='1.0812'/>
        let pattern = #/currency='([A-Z]{3})'\s+rate='([0-9.]+)'/#
        for match in xml.matches(of: pattern) {
            if let rate = Double(match.2) { rates.perEuro[String(match.1)] = rate }
        }
        guard rates.perEuro.count > 1 else { return cached }
        if let data = try? JSONEncoder().encode(rates) { try? data.write(to: file, options: .atomic) }
        return rates
    }

    /// The sum in `target`, and what couldn't be converted (currencies the ECB doesn't list), left as it is.
    func total(_ sums: [String: Double], in target: String) -> (total: Double, rest: [String: Double]) {
        var total = 0.0
        var rest: [String: Double] = [:]
        for (currency, amount) in sums {
            if let from = perEuro[currency], let to = perEuro[target] {
                total += amount / from * to
            } else {
                rest[currency] = amount
            }
        }
        return (total, rest)
    }
}

/// The currency totals are shown in: the user's choice, by default the device's.
enum DisplayCurrency {
    static let key = "displayCurrency"
    static let choices = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "SEK", "NOK", "DKK", "PLN", "CZK"]

    static var current: String {
        UserDefaults(suiteName: AppGroup.id)?.string(forKey: key)
            ?? (choices.contains(Locale.current.currency?.identifier ?? "") ? Locale.current.currency!.identifier : "EUR")
    }

    static func set(_ code: String) {
        UserDefaults(suiteName: AppGroup.id)?.set(code, forKey: key)
    }
}
