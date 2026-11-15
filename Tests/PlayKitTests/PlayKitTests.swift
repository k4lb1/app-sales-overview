import Foundation
import Security
import Testing
@testable import PlayKit

/// What can be checked without a Google account: the key, the token's signature, the report files and the sums.
/// The report contents follow Google's documented columns; the real files are only seen with a Play account.
struct PlayKitTests {
    @Test func bucketFromWhatTheConsoleShows() {
        #expect(PlayAccount.bucket(from: "gs://pubsite_prod_rev_0123456789/stats/installs/") == "pubsite_prod_rev_0123456789")
        #expect(PlayAccount.bucket(from: " pubsite_prod_42 ") == "pubsite_prod_42")
    }

    @Test func installsAreFoundByColumnNameInUTF16() throws {
        let csv = """
        Package Name,Date,Daily Device Installs,Daily User Installs,Daily User Uninstalls,Active Device Installs
        com.example.app,2026-11-01,12,10,3,500
        com.example.app,2026-11-02,8,7,1,506

        """
        var data = Data([0xFF, 0xFE])
        data.append(csv.data(using: .utf16LittleEndian)!)
        let rows = PlayReports.installs(data)
        #expect(rows.count == 2)
        #expect(rows[0] == PlayInstallRow(day: "2026-11-01", package: "com.example.app", country: nil, installs: 10, uninstalls: 3))
    }

    @Test func quotedFieldsKeepTheirCommas() {
        #expect(PlayReports.rows("a,\"b, c\",\"d \"\"e\"\"\"\n1,2,3\n") == [["a", "b, c", "d \"e\""], ["1", "2", "3"]])
    }

    @Test func salesComeOutOfTheZipStoredOrDeflated() throws {
        let csv = """
        Order Number,Order Charged Date,Financial Status,Product ID,Item Price,Currency of Sale,Country of Buyer
        GPA.1,2026-11-01,Charged,com.example.app,2.99,EUR,DE
        GPA.2,2026-11-01,Refund,com.example.app,2.99,EUR,DE

        """
        for deflate in [false, true] {
            let rows = PlayReports.sales(try zip("salesreport_202611.csv", Data(csv.utf8), deflate: deflate))
            #expect(rows.count == 2)
            #expect(rows[0].amount == 2.99 && !rows[0].isRefund)
            #expect(rows[1].amount == -2.99 && rows[1].isRefund)
        }
    }

    @Test func earningsSortChargesFeesTaxesAndRefunds() throws {
        let csv = """
        Description,Transaction Date,Transaction Time,Tax Type,Transaction Type,Refund Type,Product Title,Product id,Buyer Country,Buyer Currency,Amount (Buyer Currency),Currency Conversion Rate,Merchant Currency,Amount (Merchant Currency)
        GPA.1,"Nov 3, 2026",10:00:00 PST,,Charge,,Example,com.example.app,US,USD,3.99,0.93,EUR,3.71
        GPA.1,"Nov 3, 2026",10:00:00 PST,,Google fee,,Example,com.example.app,US,USD,-0.60,0.93,EUR,-0.56
        GPA.2,"Nov 4, 2026",11:00:00 PST,VAT,Tax,,Example,com.example.app,DE,EUR,-0.48,1,EUR,-0.48
        GPA.3,"Nov 5, 2026",12:00:00 PST,,Charge refund,Full,Example,com.example.app,DE,EUR,-2.99,1,EUR,-2.99

        """
        let rows = PlayReports.earnings(try zip("earnings_202611_0123-0.csv", Data(csv.utf8), deflate: true), month: "2026-11")
        #expect(rows.map(\.kind) == [.charge, .fee, .tax, .refund])
        #expect(rows[0].amount == 3.71 && rows[0].currency == "EUR" && rows[0].date == "Nov 3, 2026")
        #expect(rows.reduce(0) { $0 + $1.amount } == 3.71 - 0.56 - 0.48 - 2.99)
    }

    @Test func theTokenRequestIsSignedWithTheKey() async throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let key = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(key, nil)) as Data
        let pem = "-----BEGIN PRIVATE KEY-----\n" + pkcs8(pkcs1).base64EncodedString(options: .lineLength64Characters)
            + "\n-----END PRIVATE KEY-----\n"
        let json = try JSONSerialization.data(withJSONObject: ["client_email": "monitor@example.iam.gserviceaccount.com",
                                                               "private_key": pem, "token_uri": "https://oauth2.googleapis.com/token"])
        let source = try TokenSource(account: try ServiceAccount(json: json), scopes: PlayClient.scopes)
        let parts = try await source.assertion(now: Date(timeIntervalSince1970: 1_800_000_000)).split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        let claims = try #require(try JSONSerialization.jsonObject(with: base64URL(parts[1])) as? [String: Any])
        #expect(claims["iss"] as? String == "monitor@example.iam.gserviceaccount.com")
        #expect(claims["exp"] as? Int == 1_800_003_600)
        let publicKey = try #require(SecKeyCopyPublicKey(key))
        #expect(SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, Data("\(parts[0]).\(parts[1])".utf8) as CFData,
                                      base64URL(parts[2]) as CFData, nil))
    }

    @Test func sumsCountBackFromTheNewestDay() {
        let app = PlayApp(id: "com.example.app", name: "Example")
        let figures = PlayFigures(apps: [app], installs: [
            PlayInstallRow(day: "2026-11-01", package: app.id, installs: 5, uninstalls: 0),
            PlayInstallRow(day: "2026-11-02", package: app.id, installs: 7, uninstalls: 0),
            PlayInstallRow(day: "2026-11-03", package: app.id, installs: 9, uninstalls: 0),
        ], sales: [
            PlaySaleRow(day: "2026-11-03", package: app.id, country: "DE", currency: "EUR", amount: 10, isRefund: false),
            PlaySaleRow(day: "2026-11-03", package: app.id, country: "DE", currency: "EUR", amount: -10, isRefund: true),
            PlaySaleRow(day: "2026-11-02", package: app.id, country: "DE", currency: "EUR", amount: 10, isRefund: false),
        ])
        #expect(figures.installs(days: 1) == 9)
        #expect(figures.installs(days: 2) == 16)
        #expect(figures.installs(days: 1, previous: true) == 7)
        #expect(figures.proceeds(days: 2)["EUR"] == 10 * PlayFigures.afterFee)
        #expect(figures.refunds(days: 1) == 1)
    }

    // MARK: Helpers

    /// The PKCS#8 wrapper Google's JSON keys come in, around a PKCS#1 RSA key.
    private func pkcs8(_ pkcs1: Data) -> Data {
        func der(_ tag: UInt8, _ content: Data) -> Data {
            var out = Data([tag])
            if content.count < 0x80 { out.append(UInt8(content.count)) } else {
                let length = withUnsafeBytes(of: UInt32(content.count).bigEndian, Array.init).drop { $0 == 0 }
                out.append(0x80 | UInt8(length.count)); out.append(contentsOf: length)
            }
            return out + content
        }
        let algorithm = der(0x30, Data([0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00]))
        return der(0x30, Data([0x02, 0x01, 0x00]) + algorithm + der(0x04, pkcs1))
    }

    private func base64URL(_ text: String) -> Data {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)!
    }

    /// A one-file ZIP, stored or deflated, with the central directory the reader goes by.
    private func zip(_ name: String, _ content: Data, deflate: Bool) throws -> Data {
        let body = deflate ? try (content as NSData).compressed(using: .zlib) as Data : content
        func u16(_ v: Int) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
        func u32(_ v: Int) -> Data { u16(v & 0xffff) + u16(v >> 16) }
        let method = deflate ? 8 : 0, nameData = Data(name.utf8)
        let local: [Data] = [u32(0x0403_4b50), u16(20), u16(0), u16(method), u32(0), u32(0), u32(body.count), u32(content.count),
                             u16(nameData.count), u16(0), nameData, body]
        let central: [Data] = [u32(0x0201_4b50), u16(20), u16(20), u16(0), u16(method), u32(0), u32(0), u32(body.count),
                               u32(content.count), u16(nameData.count), u16(0), u16(0), u16(0), u16(0), u32(0), u32(0), nameData]
        let localData = local.reduce(Data(), +), centralData = central.reduce(Data(), +)
        let end: [Data] = [u32(0x0605_4b50), u16(0), u16(0), u16(1), u16(1), u32(centralData.count), u32(localData.count), u16(0)]
        return localData + centralData + end.reduce(Data(), +)
    }
}
