import Foundation
import Testing
@testable import ASCKit

/// Which cached days are asked for again.
struct ReportCacheTests {
    let now = ReportDay.date("2026-11-19")!.addingTimeInterval(12 * 3600)
    let row = SalesRow(title: "Spur", sku: "spur", appleID: "6832329130", parentSKU: "", productType: "1", units: 3,
                       proceeds: 0, proceedsCurrency: "EUR", country: "DE", device: "iPhone", version: "1.0")

    @Test func emptyRecentDayIsAskedForAgain() {
        #expect(!ReportCache.isSettled([], day: "2026-11-18", now: now))
        #expect(!ReportCache.isSettled([], day: "2026-11-16", now: now))
    }

    @Test func olderOrFilledDaysStay() {
        #expect(ReportCache.isSettled([], day: "2026-11-15", now: now))
        #expect(ReportCache.isSettled([row], day: "2026-11-18", now: now))
    }
}
