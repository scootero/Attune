import XCTest
@testable import Pondera

final class TranscriptRetentionTests: XCTestCase {
    func testJoinedTranscriptKeepsRawWordsThatAreMissingFromTrustedText() {
        let session = Session(
            id: "session",
            segments: [
                segment(index: 0, raw: "I would like to improve my finances", trusted: "I improve finances")
            ]
        )

        XCTAssertEqual(session.joinedTranscript(), "I would like to improve my finances")
    }

    func testJoinedTranscriptPreservesRawSegmentOrder() {
        let session = Session(
            id: "session",
            segments: [
                segment(index: 1, raw: "second segment"),
                segment(index: 0, raw: "first segment")
            ]
        )

        XCTAssertEqual(session.joinedTranscript(), "first segment\n\nsecond segment")
    }

    func testLowTrustSegmentsRemainIneligibleForExtraction() {
        var lowTrust = segment(index: 0, raw: "unclear words")
        lowTrust.transcriptQuality = "lowTrust"
        XCTAssertFalse(lowTrust.shouldAllowExtraction)

        var mixed = segment(index: 1, raw: "mostly clear words")
        mixed.transcriptQuality = "mixed"
        XCTAssertTrue(mixed.shouldAllowExtraction)
    }

    private func segment(index: Int, raw: String, trusted: String? = nil) -> Segment {
        Segment(
            id: "segment-\(index)",
            sessionId: "session",
            index: index,
            audioFileName: "segment_\(index).m4a",
            status: "done",
            transcriptText: raw,
            trustedTranscriptText: trusted
        )
    }
}
