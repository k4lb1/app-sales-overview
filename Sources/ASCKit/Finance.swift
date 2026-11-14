import Foundation

/// One line of Apple's monthly financial report: what a product earned in one currency, the basis of the payment.
/// Fields as documented: developer.apple.com/help/app-store-connect/reference/financial-report-fields
public struct FinanceRow: Codable, Hashable, Sendable {
    public var title: String
    public var appleID: String
    public var quantity: Int
    /// Quantity times the proceeds per unit, negative for returns.
    public var amount: Double
    public var currency: String
    public var country: String
}

extension Client {
    /// The financial report of one of Apple's fiscal months ("yyyy-MM"), all regions together.
    /// Empty when nothing was earned; Apple publishes a month some days after it ends.
    public func financeReport(vendor: String, month: String) async throws -> [FinanceRow] {
        do {
            let data = try await get("/v1/financeReports", query: [
                "filter[regionCode]": "ZZ", "filter[reportType]": "FINANCIAL",
                "filter[vendorNumber]": vendor, "filter[reportDate]": month,
            ])
            return FinanceRow.parse(String(decoding: try Gzip.unzip(data), as: UTF8.self))
        } catch ASCError.http(404, let body) {
            if body.contains("no sales") { return [] }
            if body.contains("not available") { throw SalesReportError.notYet }
            throw ASCError.http(404, body)
        }
    }
}

extension FinanceRow {
    /// The report ends with total lines; only lines with a currency and an amount are kept.
    static func parse(_ text: String) -> [FinanceRow] {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of: name) }
        let title = column("Title"), appleID = column("Apple Identifier"), quantity = column("Quantity"),
            amount = column("Extended Partner Share"), currency = column("Partner Share Currency"), country = column("Country Of Sale") ?? column("Country of Sale")
        func value(_ fields: [String], _ index: Int?) -> String {
            guard let index, index < fields.count else { return "" }
            return fields[index].trimmingCharacters(in: .whitespaces)
        }
        return lines.dropFirst().compactMap { fields in
            let code = value(fields, currency)
            guard code.count == 3, let total = Double(value(fields, amount)) else { return nil }
            return FinanceRow(title: value(fields, title), appleID: value(fields, appleID), quantity: Int(value(fields, quantity)) ?? 0,
                              amount: total, currency: code, country: value(fields, country))
        }
    }
}
