import XCTest
@testable import Pondera

final class ExtractorServiceCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    func testSpokenFridayOverridesIncorrectProviderDateAndTime() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12, minute: 50))
        )
        let providerCandidate = CalendarCandidate(
            suggestedTitle: "Work Meeting",
            startISO8601: "2026-09-23T15:00:00-05:00",
            endISO8601: nil,
            isAllDay: false,
            notes: nil
        )

        let normalized = ExtractorService.normalizedCalendarCandidate(
            providerCandidate,
            itemType: ExtractedItem.ItemType.event,
            sourceQuote: "I have a work meeting on Friday at 10 AM",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let start = try XCTUnwrap(normalized?.startISO8601.flatMap(ISO8601DateFormatter().date))
        XCTAssertEqual(calendar.component(.year, from: start), 2026)
        XCTAssertEqual(calendar.component(.month, from: start), 9)
        XCTAssertEqual(calendar.component(.day, from: start), 18)
        XCTAssertEqual(calendar.component(.hour, from: start), 10)
    }

    func testSpokenFridayOverridesPreviousDayProviderDate() throws {
        let referenceDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12, minute: 50))
        )
        let providerCandidate = CalendarCandidate(
            suggestedTitle: "Leave for Flight",
            startISO8601: "2026-09-16T14:00:00-05:00",
            endISO8601: nil,
            isAllDay: false,
            notes: nil
        )

        let normalized = ExtractorService.normalizedCalendarCandidate(
            providerCandidate,
            itemType: ExtractedItem.ItemType.event,
            sourceQuote: "leave by 2 PM on Friday to catch my flight",
            referenceDate: referenceDate,
            calendar: calendar
        )

        let start = try XCTUnwrap(normalized?.startISO8601.flatMap(ISO8601DateFormatter().date))
        XCTAssertEqual(calendar.component(.day, from: start), 18)
        XCTAssertEqual(calendar.component(.hour, from: start), 14)
    }

    func testCandidateRemainsUnchangedWithoutDeterministicSpokenDateOrTime() {
        let candidate = CalendarCandidate(
            suggestedTitle: "Conference",
            startISO8601: "2026-10-04",
            endISO8601: nil,
            isAllDay: false,
            notes: nil
        )

        let normalized = ExtractorService.normalizedCalendarCandidate(
            candidate,
            itemType: ExtractedItem.ItemType.event,
            sourceQuote: "the conference is in early October",
            referenceDate: Date(),
            calendar: calendar
        )

        XCTAssertEqual(normalized?.startISO8601, candidate.startISO8601)
    }
}
