import SwiftUI

extension Color {
    /// True black, so the OLED screen is off around the numbers.
    static let ground = Color.black
    static let card = Color.white.opacity(0.06)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let sales = Color(white: 0.86)
}

extension View {
    func card() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.card, in: .rect(cornerRadius: 20))
    }
}

/// App Store Connect's version states in plain words, with a colour.
struct VersionState {
    let title: LocalizedStringKey
    let color: Color

    init(_ state: String) {
        switch state {
        case "READY_FOR_DISTRIBUTION": (title, color) = ("In the store", .green)
        case "PENDING_DEVELOPER_RELEASE", "PENDING_APPLE_RELEASE": (title, color) = ("Approved, not released", .sales)
        case "WAITING_FOR_REVIEW": (title, color) = ("Waiting for review", .orange)
        case "IN_REVIEW": (title, color) = ("In review", .orange)
        case "PROCESSING_FOR_DISTRIBUTION": (title, color) = ("Processing", .orange)
        case "REJECTED", "METADATA_REJECTED", "INVALID_BINARY": (title, color) = ("Rejected", .red)
        case "DEVELOPER_REJECTED": (title, color) = ("Withdrawn", .gray)
        case "PREPARE_FOR_SUBMISSION": (title, color) = ("Being prepared", .gray)
        case "REPLACED_WITH_NEW_VERSION", "DEVELOPER_REMOVED_FROM_SALE", "REMOVED_FROM_SALE": (title, color) = ("Not in the store", .gray)
        default: (title, color) = (LocalizedStringKey(state.replacingOccurrences(of: "_", with: " ").capitalized), .gray)
        }
    }
}

struct StatePill: View {
    let version: StoreApp.Version

    var body: some View {
        let state = VersionState(version.state)
        HStack(spacing: 5) {
            Circle().fill(state.color).frame(width: 7, height: 7)
            Text(version.string).monospacedDigit()
            Text(state.title)
        }
        .lineLimit(1)
        .font(.caption.weight(.medium))
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(state.color.opacity(0.18), in: .capsule)
        .fixedSize()
    }
}

struct AppIcon: View {
    let app: StoreApp
    let url: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { image in image.resizable() } placeholder: { Color.card }
            } else {
                Text(app.name.prefix(1).uppercased()).font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.card)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
    }
}
