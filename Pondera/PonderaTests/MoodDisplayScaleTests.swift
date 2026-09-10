import XCTest
@testable import Pondera

final class MoodDisplayScaleTests: XCTestCase {
    func testStoredScoresMapToCenteredScale() {
        XCTAssertEqual(MoodDisplayScale.centeredValue(forStoredScore: 0), -5)
        XCTAssertEqual(MoodDisplayScale.centeredValue(forStoredScore: 5), 0)
        XCTAssertEqual(MoodDisplayScale.centeredValue(forStoredScore: 10), 5)
    }

    func testCenteredValuesRoundTripToStorage() {
        for centeredValue in -5...5 {
            let storedScore = MoodDisplayScale.storedScore(forCenteredValue: centeredValue)
            XCTAssertEqual(MoodDisplayScale.centeredValue(forStoredScore: storedScore), centeredValue)
        }
    }

    func testEveryIncrementHasItsOwnFace() {
        let faces = (0...10).map(MoodDisplayScale.emoji(forStoredScore:))
        XCTAssertEqual(Set(faces).count, 11)
    }

    func testPositiveValuesIncludePlusSign() {
        XCTAssertEqual(MoodDisplayScale.formattedCenteredValue(forStoredScore: 7), "+2")
        XCTAssertEqual(MoodDisplayScale.formattedCenteredValue(forStoredScore: 5), "0")
        XCTAssertEqual(MoodDisplayScale.formattedCenteredValue(forStoredScore: 3), "-2")
    }

    func testFeelingSelectorOptionsStayUnique() {
        XCTAssertEqual(MoodDisplayScale.feelingLabels.count, 8)
        XCTAssertEqual(Set(MoodDisplayScale.feelingLabels).count, MoodDisplayScale.feelingLabels.count)
    }
}
