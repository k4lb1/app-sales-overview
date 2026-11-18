import Foundation
import Testing
@testable import ASCKit

/// Parsing of Apple's crash and session reports, based on the documented report format.
struct UsageTests {
    @Test func crashLinesAddUpPerDayAndApp() {
        let text = """
        Date\tApp Name\tApp Apple Identifier\tApp Version\tDevice\tPlatform Version\tCrashes\tUnique Devices
        2026-11-14\tSpur\t6832329130\t1.0\tiPhone\t26.1\t3\t2
        2026-11-14\tSpur\t6832329130\t1.1\tiPad\t26.1\t2\t2
        2026-11-14\tMitte\t6832000000\t1.0\tiPhone\t26.1\t1\t1
        """
        let rows = UsageRow.parse(text)
        #expect(rows == [UsageRow(date: "2026-11-14", appID: "6832000000", crashes: 1, sessions: 0),
                         UsageRow(date: "2026-11-14", appID: "6832329130", crashes: 5, sessions: 0)])
    }

    @Test func sessionsCountAndGiveTheRate() {
        let text = """
        Date\tApp Name\tApp Apple Identifier\tApp Version\tDevice\tPlatform Version\tSource Type\tPage Type\tApp Download Date\tTerritory\tSessions\tTotal Session Duration\tUnique Devices
        2026-11-14\tSpur\t6832329130\t1.0\tiPhone\t26.1\tApp Store search\tProduct page\t\tDE\t600\t9000\t80
        2026-11-14\tSpur\t6832329130\t1.0\tiPhone\t26.1\tApp referrer\tNo page\t\tUS\t400\t6000\t50
        """
        let sessions = UsageRow.parse(text)
        #expect(sessions == [UsageRow(date: "2026-11-14", appID: "6832329130", crashes: 0, sessions: 1000)])
        let app = StoreApp(id: "6832329130", name: "Spur", bundleID: "", sku: "", versions: [])
        let figures = Figures(apps: [app], usage: [UsageRow(date: "2026-11-14", appID: app.id, crashes: 5, sessions: 1000)])
        #expect(figures.crashesPerThousand(app: app)?.value == 5)
    }
}
