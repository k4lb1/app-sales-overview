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
                      preview: SharePreview("Daily figures (\(label))")) {
                Label("Daily figures", systemImage: "calendar")
            }
            ShareLink(item: CSVFile(name: "App Sales \(label) countries", text: dashboard.figures.countriesCSV(days: days)),
                      preview: SharePreview("Countries (\(label))")) {
                Label("Countries", systemImage: "globe")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Export as CSV")
    }

    private var label: String { days == 1 ? "yesterday" : "\(days) days" }
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
