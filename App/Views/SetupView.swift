import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    @Environment(Dashboard.self) private var dashboard
    @State private var issuer = ""
    @State private var keyID = ""
    @State private var vendor = ""
    @State private var pem = ""
    @State private var importsKey = false
    @State private var isChecking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("All your apps at a glance").font(.title2.weight(.semibold))
                    Text("Downloads, proceeds and review status of every app, read straight from App Store Connect with your own API key. The key stays on this iPhone and only ever goes to Apple.")
                        .font(.callout).foregroundStyle(Color.muted)
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Text("1. In App Store Connect, open Users and Access › Integrations › Team Keys.")
                Text("2. Generate a key with the Finance or Admin role and download it (.p8, only possible once).")
                Text("3. Copy the Issuer ID (above the list) and the Key ID (in the key's row).")
                Text("4. The vendor number is in Payments and Financial Reports, top left.")
            } header: {
                Text("How to get a key")
            }
            .font(.callout)

            Section("Your key") {
                TextField("Issuer ID", text: $issuer).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Key ID", text: $keyID).textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Vendor number", text: $vendor).keyboardType(.numberPad)
                Button {
                    importsKey = true
                } label: {
                    LabeledContent("Private key (.p8)") { Text(pem.isEmpty ? "Choose file" : "Loaded") }
                }
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        Spacer()
                        if isChecking { ProgressView() } else { Text("Connect").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(!isComplete || isChecking)
                Button {
                    dashboard.startDemo()
                } label: {
                    Text("Try with sample data").frame(maxWidth: .infinity)
                }
            } footer: {
                Text("Sample data shows every feature with invented apps and figures, without a key.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.ground.ignoresSafeArea())
        .fileImporter(isPresented: $importsKey, allowedContentTypes: [.data, .plainText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let text = try? String(contentsOf: url, encoding: .utf8), text.contains("PRIVATE KEY") else {
                error = String(localized: "That isn't a .p8 key file.")
                return
            }
            pem = text
            error = nil
            // The file is called AuthKey_<Key ID>.p8, so the Key ID can be filled in.
            let name = url.deletingPathExtension().lastPathComponent
            if keyID.isEmpty, name.hasPrefix("AuthKey_") { keyID = String(name.dropFirst(8)) }
        }
    }

    private var isComplete: Bool {
        !issuer.isEmpty && !keyID.isEmpty && !vendor.isEmpty && !pem.isEmpty
    }

    private func connect() async {
        isChecking = true
        defer { isChecking = false }
        let account = Account(issuer: issuer.trimmingCharacters(in: .whitespaces), keyID: keyID.trimmingCharacters(in: .whitespaces),
                              privateKeyPEM: pem, vendorNumber: vendor.trimmingCharacters(in: .whitespaces))
        do {
            try await dashboard.connect(account)
        } catch ASCError.http(401, _) {
            error = String(localized: "Apple didn't accept the key. Check the Issuer ID, the Key ID and the .p8 file.")
        } catch let failure as URLError {
            error = failure.localizedDescription
        } catch {
            self.error = String(describing: error)
        }
    }
}
