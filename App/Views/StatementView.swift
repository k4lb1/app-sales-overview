import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A month for the books, as a PDF to keep or pass on, and as CSV.
struct StatementView: View {
    @Environment(Dashboard.self) private var dashboard
    @Environment(\.dismiss) private var dismiss
    @State private var month: String?
    @State private var pdf: Data?

    var body: some View {
        let months = dashboard.figures.statementMonths
        let month = month ?? months.first
        NavigationStack {
            Group {
                if let month {
                    content(dashboard.figures.statement(month), months: months)
                } else {
                    ContentUnavailableView("No month yet", systemImage: "doc.text",
                                           description: Text("Apple publishes a month's sales summary a few days after it ends."))
                }
            }
            .background(Color.ground.ignoresSafeArea())
            .navigationTitle("Monthly statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func content(_ statement: Statement, months: [String]) -> some View {
        let rates = dashboard.figures.rates
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Month", selection: Binding(get: { statement.month }, set: { month = $0 })) {
                    ForEach(months, id: \.self) { Text(Statement.title($0)).tag($0) }
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 12) {
                    amount("Proceeds", statement.total)
                    if !statement.payout.isEmpty { amount("Apple's financial report", statement.payoutConverted) }
                    ForEach(statement.apps, id: \.app) { app in
                        HStack {
                            Text(app.app).lineLimit(1)
                            Spacer()
                            Text(app.converted.formatted(.currency(code: statement.currency))).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .card()

                HStack(spacing: 12) {
                    if let pdf {
                        ShareLink(item: PDFFile(name: "App Sales \(statement.month)", data: pdf),
                                  preview: SharePreview("Statement \(statement.title)")) {
                            Label("PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity)
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    ShareLink(item: CSVFile(name: "App Sales \(statement.month)", text: statement.csv()),
                              preview: SharePreview("Statement \(statement.title)")) {
                        Label("CSV", systemImage: "tablecells").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("From Apple's monthly sales summary: proceeds after Apple's commission and the taxes it collects. Converted at the ECB's rate, for an overview. What Apple actually paid is on your bank statement.")
                    .font(.caption).foregroundStyle(Color.muted)
            }
            .padding(16)
        }
        .task(id: statement.month + statement.currency) {
            pdf = nil
            pdf = StatementPDF.render(statement, rates: rates)
        }
    }

    private func amount(_ title: LocalizedStringKey, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Color.muted)
            Text(value.formatted(.currency(code: DisplayCurrency.current))).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }
}

struct PDFFile: Transferable {
    let name: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { file in
            let url = URL.temporaryDirectory.appending(path: "\(file.name).pdf")
            try file.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// The statement on A4 pages: the summary first, then every app and country.
enum StatementPDF {
    private static let size = CGSize(width: 595, height: 842)
    private static let linesPerPage = 36

    @MainActor
    static func render(_ statement: Statement, rates: Rates) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let chunks = stride(from: 0, to: statement.lines.count, by: linesPerPage).map { Array(statement.lines[$0..<min($0 + linesPerPage, statement.lines.count)]) }
        let pages: [AnyView] = [AnyView(summary(statement, rates: rates))] + chunks.map { AnyView(lines($0, statement: statement)) }
        for (index, page) in pages.enumerated() {
            let renderer = ImageRenderer(content: Page(statement: statement, number: index + 1, of: pages.count) { page })
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    private struct Page<Content: View>: View {
        let statement: Statement
        let number: Int
        let of: Int
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Statement \(statement.title)").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Text(verbatim: "App Sales Overview").font(.system(size: 9)).foregroundStyle(.gray)
                }
                content
                Spacer(minLength: 0)
                HStack {
                    Text("Made \(Date.now.formatted(date: .long, time: .omitted))")
                    Spacer()
                    Text("Page \(number) of \(of)")
                }
                .font(.system(size: 8)).foregroundStyle(.gray)
            }
            .padding(40)
            .frame(width: StatementPDF.size.width, height: StatementPDF.size.height, alignment: .topLeading)
            .background(.white)
            .foregroundStyle(.black)
            .environment(\.colorScheme, .light)
        }
    }

    private static func summary(_ statement: Statement, rates: Rates) -> some View {
        let money = { (value: Double) in value.formatted(.currency(code: statement.currency)) }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 40) {
                figure(String(localized: "Proceeds"), money(statement.total))
                if !statement.payout.isEmpty { figure(String(localized: "Apple's financial report"), money(statement.payoutConverted)) }
            }
            table(String(localized: "Per app"), [app, downloads, inApp, refunds, proceeds], statement.apps.map {
                [$0.app, "\($0.downloads)", "\($0.purchases)", "\($0.refunds)", money($0.converted)]
            })
            table(String(localized: "Per currency, as Apple reports it"), [currency, proceeds, statement.currency], statement.currencies.map {
                [$0.currency, $0.proceeds.formatted(.number.precision(.fractionLength(2))), money($0.converted)]
            })
            if !statement.payout.isEmpty {
                table(String(localized: "Apple's financial report"), [currency, String(localized: "Amount"), statement.currency],
                      statement.payout.sorted { $0.key < $1.key }.map {
                    [$0.key, $0.value.formatted(.number.precision(.fractionLength(2))),
                     money(rates.total([$0.key: $0.value], in: statement.currency).total)]
                })
            }
            Text("Proceeds are what Apple reports for the developer in its monthly sales summary, after its commission and the taxes it collects and pays itself. Amounts in \(statement.currency) are converted at the European Central Bank's reference rates of \(rates.fetched.formatted(date: .long, time: .omitted)), for an overview. The amount Apple actually paid, at its own rate and after any tax it withheld, is on your bank statement.")
                .font(.system(size: 8)).foregroundStyle(.gray).fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func lines(_ lines: [Statement.Line], statement: Statement) -> some View {
        table(String(localized: "Per app and country"), [app, String(localized: "Country"), downloads, inApp, refunds, proceeds, statement.currency],
              leading: 2, lines.map {
            [$0.app, Figures.countryName($0.country), "\($0.downloads)", "\($0.purchases)", "\($0.refunds)",
             $0.currency.isEmpty ? "–" : "\($0.proceeds.formatted(.number.precision(.fractionLength(2)))) \($0.currency)",
             $0.converted.formatted(.currency(code: statement.currency))]
        })
    }

    private static func figure(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.gray)
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
        }
    }

    private static var app: String { String(localized: "App") }
    private static var downloads: String { String(localized: "Downloads") }
    private static var inApp: String { String(localized: "In-app") }
    private static var refunds: String { String(localized: "Refunds") }
    private static var proceeds: String { String(localized: "Proceeds") }
    private static var currency: String { String(localized: "Currency") }

    /// The first `leading` columns left, the others right-aligned numbers.
    private static func table(_ title: String, _ header: [String], leading: Int = 1, _ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold))
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    ForEach(header.indices, id: \.self) { index in
                        Text(header[index]).gridColumnAlignment(index < leading ? .leading : .trailing)
                    }
                }
                .font(.system(size: 8, weight: .medium)).foregroundStyle(.gray)
                Divider()
                ForEach(rows.indices, id: \.self) { row in
                    GridRow {
                        ForEach(rows[row].indices, id: \.self) { index in
                            Text(rows[row][index]).lineLimit(1)
                        }
                    }
                    .font(.system(size: 9)).monospacedDigit()
                }
            }
        }
    }
}
