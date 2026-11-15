import Foundation

/// One day of one app from the installs report; with a country when it comes from the per-country file.
public struct PlayInstallRow: Codable, Hashable, Sendable {
    /// "yyyy-MM-dd", Pacific time.
    public var day: String
    public var package: String
    public var country: String?
    public var installs: Int
    public var uninstalls: Int
}

/// One order or refund from the monthly sales report.
public struct PlaySaleRow: Codable, Hashable, Sendable {
    public var day: String
    public var package: String
    public var country: String
    public var currency: String
    /// The item's price without tax, as the buyer paid it; negative for a refund.
    public var amount: Double
    public var isRefund: Bool
}

/// One booking from Google's monthly earnings report, in the payout currency at Google's own rate: what reaches the
/// bank, so the figure the books want.
public struct PlayEarningRow: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case charge, fee, tax, refund
    }

    /// "yyyy-MM", the month of the report.
    public var month: String
    /// As Google writes it, e.g. "Nov 3, 2026".
    public var date: String
    public var kind: Kind
    /// Google's own word for it, e.g. "Charge", "Google fee", "Tax", "Charge refund".
    public var type: String
    public var package: String
    public var country: String
    /// In the payout currency; fees, taxes and refunds are negative, as in the report.
    public var amount: Double
    public var currency: String
}

/// The Play Console's report files. Google says not to count on the order of the columns, so they're found by name.
public enum PlayReports {
    /// `stats/installs/installs_<package>_<yyyyMM>_overview.csv` or `…_country.csv`, UTF-16 with a byte order mark.
    public static func installs(_ data: Data) -> [PlayInstallRow] {
        let table = rows(text(data))
        guard let header = table.first else { return [] }
        let column = Columns(header)
        guard let date = column["Date"], let package = column["Package Name", "Package name"],
              let installs = column["Daily User Installs", "Install events", "Daily Device Installs"] else { return [] }
        let uninstalls = column["Daily User Uninstalls", "Uninstall events", "Daily Device Uninstalls"]
        let country = column["Country"]
        return table.dropFirst().compactMap { row in
            guard row.count > max(date, package, installs), !row[date].isEmpty else { return nil }
            return PlayInstallRow(day: row[date], package: row[package], country: country.flatMap { $0 < row.count ? row[$0] : nil },
                                  installs: Int(row[installs]) ?? 0, uninstalls: uninstalls.flatMap { $0 < row.count ? Int(row[$0]) : nil } ?? 0)
        }
    }

    /// `sales/salesreport_<yyyyMM>.zip`: a CSV of every order of the month, refunds as their own lines.
    public static func sales(_ zip: Data) -> [PlaySaleRow] {
        guard let csv = (try? Zip.files(zip))?.first(where: { $0.name.hasSuffix(".csv") })?.data else { return [] }
        let table = rows(text(csv))
        guard let header = table.first else { return [] }
        let column = Columns(header)
        guard let date = column["Order Charged Date"], let product = column["Product ID"], let price = column["Item Price"],
              let currency = column["Currency of Sale"] else { return [] }
        let status = column["Financial Status"], country = column["Country of Buyer"]
        return table.dropFirst().compactMap { row in
            guard row.count > max(date, product, price, currency) else { return nil }
            let refund = status.map { $0 < row.count && row[$0].localizedCaseInsensitiveContains("refund") } ?? false
            let amount = Double(row[price].replacingOccurrences(of: ",", with: "")) ?? 0
            return PlaySaleRow(day: row[date], package: row[product], country: country.map { $0 < row.count ? row[$0] : "" } ?? "",
                               currency: row[currency], amount: refund ? -abs(amount) : amount, isRefund: refund)
        }
    }

    /// `earnings/earnings_<yyyyMM>_<account>-<n>.zip`: every booking of the month in the payout currency.
    public static func earnings(_ zip: Data, month: String) -> [PlayEarningRow] {
        guard let csv = (try? Zip.files(zip))?.first(where: { $0.name.hasSuffix(".csv") })?.data else { return [] }
        let table = rows(text(csv))
        guard let header = table.first else { return [] }
        let column = Columns(header)
        guard let type = column["Transaction Type"], let amount = column["Amount (Merchant Currency)", "Merchant Currency Amount"],
              let currency = column["Merchant Currency"] else { return [] }
        let date = column["Transaction Date"], product = column["Product id", "Product ID"], country = column["Buyer Country"]
        func field(_ row: [String], _ index: Int?) -> String { index.map { $0 < row.count ? row[$0] : "" } ?? "" }
        return table.dropFirst().compactMap { row in
            guard row.count > max(type, amount, currency), let value = Double(row[amount].replacingOccurrences(of: ",", with: "")) else { return nil }
            let word = row[type]
            let lower = word.lowercased()
            let kind: PlayEarningRow.Kind = lower.contains("fee") ? .fee : lower.contains("tax") ? .tax : lower.contains("refund") ? .refund : .charge
            return PlayEarningRow(month: month, date: field(row, date), kind: kind, type: word, package: field(row, product),
                                  country: field(row, country), amount: value, currency: row[currency])
        }
    }

    /// UTF-16 by its byte order mark, otherwise UTF-8.
    static func text(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) ?? "" }
        if bytes == [0xFE, 0xFF] { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) ?? "" }
        let text = String(decoding: data, as: UTF8.self)
        return text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// CSV with quoted fields (commas, quotes and line breaks inside quotes).
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var characters = text.makeIterator()
        while let character = characters.next() {
            if quoted {
                if character == "\"" {
                    if let following = characters.next() {
                        if following == "\"" { field.append("\"") } else {
                            quoted = false
                            if following == "," { row.append(field); field = "" }
                            else if following.isNewline { row.append(field); field = ""; rows.append(row); row = [] }
                            else { field.append(following) }
                        }
                    } else { quoted = false }
                } else { field.append(character) }
            } else if character == "\"" && field.isEmpty {
                quoted = true
            } else if character == "," {
                row.append(field); field = ""
            } else if character.isNewline {
                row.append(field); field = ""
                if row != [""] { rows.append(row) }
                row = []
            } else {
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.map { $0.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// Column positions by name; the first of several names that's there.
    private struct Columns {
        let index: [String: Int]

        init(_ header: [String]) {
            index = Dictionary(header.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        }

        subscript(_ names: String...) -> Int? {
            names.lazy.compactMap { index[$0.lowercased()] }.first
        }
    }
}

/// Reads a ZIP file's entries: stored or deflated, found through the central directory (so sizes are right even when
/// the local headers leave them out). Enough for Google's report archives.
enum Zip {
    struct Entry { let name: String; let data: Data }

    static func files(_ zip: Data) throws -> [Entry] {
        let bytes = [UInt8](zip)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count >= 22, let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x0605_4b50 }) else { return [] }
        var entries: [Entry] = []
        var at = u32(end + 16)
        for _ in 0..<u16(end + 10) {
            guard at + 46 <= bytes.count, u32(at) == 0x0201_4b50 else { break }
            let method = u16(at + 10), compressed = u32(at + 20)
            let nameLength = u16(at + 28), extra = u16(at + 30), comment = u16(at + 32), local = u32(at + 42)
            let name = String(decoding: bytes[(at + 46)..<(at + 46 + nameLength)], as: UTF8.self)
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count else { break }
            let raw = Data(bytes[start..<(start + compressed)])
            switch method {
            case 0: entries.append(Entry(name: name, data: raw))
            case 8: entries.append(Entry(name: name, data: try (raw as NSData).decompressed(using: .zlib) as Data))
            default: break
            }
            at += 46 + nameLength + extra + comment
        }
        return entries
    }
}
