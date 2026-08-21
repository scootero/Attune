import XCTest
@testable import Attune

final class WeeklyMomentumDayPresentationTests: XCTestCase {
    func testCurrentDayWithoutProgressStaysOpenUntilLocalMidnight() {
        let calendar = fixedCalendar()
        let now = date(day: 20, hour: 23, minute: 20, calendar: calendar)
        let today = momentumDay(date: date(day: 20, hour: 0, calendar: calendar))

        XCTAssertEqual(
            WeeklyMomentumDayPresentationPolicy.presentation(for: today, now: now, calendar: calendar),
            .open
        )
    }

    func testOpenDayLocksAsMissedAfterLocalMidnight() {
        let calendar = fixedCalendar()
        let yesterday = momentumDay(date: date(day: 20, hour: 0, calendar: calendar))
        let afterMidnight = date(day: 21, hour: 0, minute: 1, calendar: calendar)

        XCTAssertEqual(
            WeeklyMomentumDayPresentationPolicy.presentation(for: yesterday, now: afterMidnight, calendar: calendar),
            .missed
        )
    }

    func testRecordedProgressKeepsExistingProgressPresentation() {
        let calendar = fixedCalendar()
        let day = DayMomentum(
            date: date(day: 20, hour: 0, calendar: calendar),
            weekdayLetter: "T",
            completionRatio: 0.5,
            tier: .neutral,
            isFutureDay: false,
            hasData: true
        )

        XCTAssertEqual(
            WeeklyMomentumDayPresentationPolicy.presentation(
                for: day,
                now: date(day: 20, hour: 12, calendar: calendar),
                calendar: calendar
            ),
            .progress(0.5)
        )
    }

    private func momentumDay(date: Date) -> DayMomentum {
        DayMomentum(
            date: date,
            weekdayLetter: "T",
            completionRatio: nil,
            tier: .neutral,
            isFutureDay: false,
            hasData: false
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    private func date(
        day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
