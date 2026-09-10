import XCTest
@testable import Pondera

final class InsightSeenStoreTests: XCTestCase {
    func testUnseenIDsArePersistedAsSeen() throws {
        let suiteName = "InsightSeenStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = InsightSeenStore(defaults: defaults, key: "seen")

        XCTAssertEqual(store.unseenIDs(in: ["one", "two"]), ["one", "two"])

        store.markSeen(["one"], retaining: ["one", "two"])

        XCTAssertEqual(store.unseenIDs(in: ["one", "two"]), ["two"])
    }

    func testMarkSeenPrunesIDsThatNoLongerExist() throws {
        let suiteName = "InsightSeenStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = InsightSeenStore(defaults: defaults, key: "seen")

        store.markSeen(["old", "current"], retaining: ["old", "current"])
        store.markSeen(["new"], retaining: ["current", "new"])

        XCTAssertEqual(store.unseenIDs(in: ["old", "current", "new"]), ["old"])
    }
}
