import XCTest
@testable import Pondera

final class SessionRecapReadOnlyTests: XCTestCase {
    func testTopicSnapshotReadDoesNotMutateFileOrDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("Topics.json")
        let topic = TopicAggregate(
            canonicalKey: "planning__123456",
            displayTitle: "Planning",
            firstSeenAtISO: "2026-08-01T00:00:00Z",
            categories: [ExtractedItem.Category.personalGrowth],
            itemId: "item",
            topicKey: nil
        )
        let originalData = try JSONEncoder().encode([topic])
        try originalData.write(to: fileURL)

        let beforeFiles = try directorySnapshot(temporaryDirectory)
        let beforeData = try Data(contentsOf: fileURL)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        let loaded = SessionRecapTopicSnapshotReader.load(from: fileURL)

        let afterFiles = try directorySnapshot(temporaryDirectory)
        let afterData = try Data(contentsOf: fileURL)
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertNil(loaded.first?.topicKey, "The recap reader must not migrate legacy topics")
        XCTAssertEqual(beforeFiles, afterFiles, "No files may be created, renamed, repaired, or removed")
        XCTAssertEqual(beforeData, afterData, "Topic bytes must remain unchanged")
        XCTAssertEqual(beforeAttributes[.modificationDate] as? Date, afterAttributes[.modificationDate] as? Date)
        XCTAssertEqual(beforeAttributes[.creationDate] as? Date, afterAttributes[.creationDate] as? Date)
        XCTAssertEqual(beforeAttributes[.size] as? NSNumber, afterAttributes[.size] as? NSNumber)
    }

    func testMalformedTopicSnapshotIsNotRenamedOrRepaired() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("Topics.json")
        let malformed = Data("not-json".utf8)
        try malformed.write(to: fileURL)
        let beforeFiles = try directorySnapshot(temporaryDirectory)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

        XCTAssertEqual(SessionRecapTopicSnapshotReader.load(from: fileURL).count, 0)

        XCTAssertEqual(try directorySnapshot(temporaryDirectory), beforeFiles)
        XCTAssertEqual(try Data(contentsOf: fileURL), malformed)
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual(beforeAttributes[.modificationDate] as? Date, afterAttributes[.modificationDate] as? Date)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("Topics.corrupt.json").path))
    }

    private func directorySnapshot(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }
}
