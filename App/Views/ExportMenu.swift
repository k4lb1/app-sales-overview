import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The figures of the chosen period as CSV files, shared through the system share sheet.
struct ExportMenu: View {
    @Environment(Dashboard.self) private var dashboard
    let days: Int

    var body: some View {
        Menu {
            ShareLink(item: CSVFile(name: "App Sales \(label) daily", text: dashboard.figures.dailyCSV(days: days)),
                      preview: SharePreview("Daily figures (\(period))")) {
                Label("Daily figures", systemImage: "calendar")
            }
            ShareLink(item: CSVFile(name: "App Sales \(label) countries", text: dashboard.figures.countriesCSV(days: days)),
                      preview: SharePreview("Countries (\(period))")) {
                Label("Countries", systemImage: "globe")
            }
            ShareLink(item: CSVFile(name: "App Sales \(label) all sales", text: dashboard.figures.salesCSV(days: days)),
                      preview: SharePreview("All sales lines (\(period))")) {
                Label("All sales lines", systemImage: "list.bullet.rectangle")
            }
            if !dashboard.figures.discovery.isEmpty {
                ShareLink(item: CSVFile(name: "App Sales \(label) store", text: dashboard.figures.storeCSV(days: days)),
                          preview: SharePreview("Store analytics (\(period))")) {
                    Label("Store analytics", systemImage: "eye")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Export as CSV")
    }

    /// For the file names, in English like the files' columns.
    private var label: String { days == 1 ? "yesterday" : "\(days) days" }
    private var period: String { days == 1 ? String(localized: "yesterday") : String(localized: "\(days) days") }
}

/// Written to a temporary file only when the user picks where it goes.
struct CSVFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = URL.temporaryDirectory.appending(path: "\(file.name).csv")
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
