import CoreGraphics
import XCTest
@testable import Attune

final class MomentumDailyLayoutTests: XCTestCase {
    func testDailyDomainPadsBothSidesOfActivity() {
        let calendar = utcCalendar()
        let day = date(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let first = point(
            id: "first",
            date: date(year: 2026, month: 8, day: 10, hour: 8, minute: 23, calendar: calendar),
            intentionId: "first",
            percent: 30
        )

        let domain = DailyMomentumTimeDomain.make(points: [first], selectedDate: day, calendar: calendar)

        XCTAssertEqual(calendar.component(.hour, from: domain.start), 6)
        XCTAssertEqual(calendar.component(.hour, from: domain.end), 11)
        XCTAssertTrue(domain.omitsMidnight)
    }

    func testDailyDomainExpandsToMidnightForLateActivity() {
        let calendar = utcCalendar()
        let day = date(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let late = point(
            id: "late",
            date: date(year: 2026, month: 8, day: 10, hour: 21, minute: 15, calendar: calendar),
            intentionId: "late",
            percent: 30
        )

        let domain = DailyMomentumTimeDomain.make(points: [late], selectedDate: day, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: domain.end), 11)
        XCTAssertEqual(calendar.component(.hour, from: domain.end), 0)
    }

    func testDailyDomainUsesACompactSetOfTimeLabels() {
        let calendar = utcCalendar()
        let day = date(year: 2026, month: 8, day: 10, hour: 12, calendar: calendar)
        let first = point(
            id: "first",
            date: date(year: 2026, month: 8, day: 10, hour: 8, calendar: calendar),
            intentionId: "first",
            percent: 20
        )

        let domain = DailyMomentumTimeDomain.make(points: [first], selectedDate: day, calendar: calendar)

        XCTAssertLessThanOrEqual(domain.tickDates.count, 5)
        XCTAssertEqual(domain.tickDates.first, domain.start)
        XCTAssertEqual(domain.tickDates.last, domain.end)
    }

    func testBarEntranceWaveSettlesWithinTwoSeconds() {
        let duration = MomentumBarEntranceAnimation.totalDuration(barCount: 12)

        XCTAssertGreaterThanOrEqual(duration, 1.5)
        XCTAssertLessThanOrEqual(duration, 2.0)
        XCTAssertGreaterThan(
            MomentumBarEntranceAnimation.scale(clock: 0.25, index: 0, barCount: 12, reduceMotion: false),
            MomentumBarEntranceAnimation.scale(clock: 0.25, index: 4, barCount: 12, reduceMotion: false)
        )
        XCTAssertEqual(
            MomentumBarEntranceAnimation.scale(clock: duration, index: 11, barCount: 12, reduceMotion: false),
            1,
            accuracy: 0.001
        )
    }

    func testSameMinuteBarsKeepEqualWidthAndOrderLowToHighFromLeftToRight() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let timestamp = start.addingTimeInterval(10 * 60 * 60)
        let low = point(id: "low", date: timestamp, intentionId: "low", percent: 20)
        let high = point(id: "high", date: timestamp, intentionId: "high", percent: 60)

        let items = DailyMomentumBarLayout.makeItems(
            points: [high, low],
            dayStart: start,
            dayDuration: 24 * 60 * 60,
            chartWidth: 240,
            baseBarWidth: 28,
            minimumBarWidth: 7
        ).sorted { $0.centerX < $1.centerX }

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].point.id, "low")
        XCTAssertEqual(items[1].point.id, "high")
        XCTAssertEqual(items[0].barWidth, 28, accuracy: 0.001)
        XCTAssertEqual(items[1].barWidth, 28, accuracy: 0.001)
        XCTAssertEqual(items[1].centerX - items[0].centerX, 32, accuracy: 0.001)
        XCTAssertEqual((items[0].centerX + items[1].centerX) / 2, 100, accuracy: 0.001)
    }

    func testNearbyTimeClustersShiftWithoutChangingBarWidth() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = point(
            id: "first",
            date: start.addingTimeInterval(8 * 60 * 60),
            intentionId: "first",
            percent: 30
        )
        let secondTime = start.addingTimeInterval(10 * 60 * 60)
        let secondLow = point(id: "second-low", date: secondTime, intentionId: "second-low", percent: 20)
        let secondHigh = point(id: "second-high", date: secondTime, intentionId: "second-high", percent: 40)

        let items = DailyMomentumBarLayout.makeItems(
            points: [first, secondLow, secondHigh],
            dayStart: start,
            dayDuration: 24 * 60 * 60,
            chartWidth: 240,
            baseBarWidth: 28,
            minimumBarWidth: 7
        )
        let firstItem = try! XCTUnwrap(items.first { $0.point.id == "first" })
        let secondItems = items.filter { $0.point.id.hasPrefix("second") }

        XCTAssertLessThanOrEqual(firstItem.footprintRight + 2, secondItems.map(\.footprintLeft).min()!)
        XCTAssertTrue(items.allSatisfy { abs($0.barWidth - 28) < 0.001 })
    }

    func testManualSavePolicyIgnoresUnchangedTotalsButKeepsCorrections() {
        XCTAssertFalse(ManualProgressSavePolicy.hasChanged(current: 10, original: 10))
        XCTAssertTrue(ManualProgressSavePolicy.hasChanged(current: 19.2, original: 10))
        XCTAssertTrue(ManualProgressSavePolicy.hasChanged(current: 7, original: 10))
    }

    func testManualProgressRewardOnlyWhenCrossingTarget() {
        XCTAssertTrue(ManualProgressSavePolicy.crossedTarget(previousPercent: 0.8, currentPercent: 1))
        XCTAssertFalse(ManualProgressSavePolicy.crossedTarget(previousPercent: 1, currentPercent: 1.2))
        XCTAssertFalse(ManualProgressSavePolicy.crossedTarget(previousPercent: 0.8, currentPercent: 0.9))
    }

    func testPersistedProgressReplacesStaleSliderDraftAfterEditingEnds() {
        XCTAssertEqual(
            ManualProgressDisplayPolicy.displayedTotal(stored: 10, draft: 2, isEditing: false),
            10
        )
        XCTAssertEqual(
            ManualProgressDisplayPolicy.displayedTotal(stored: 10, draft: 2, isEditing: true),
            2
        )
    }

    func testManualProgressSliderUsesNineTicksAcrossEightEvenSegments() {
        XCTAssertEqual(ManualProgressSliderPolicy.tickPercents.count, 9)
        XCTAssertEqual(ManualProgressSliderPolicy.tickPercents.first, 0)
        XCTAssertEqual(ManualProgressSliderPolicy.tickPercents[4], 0.5)
        XCTAssertEqual(ManualProgressSliderPolicy.tickPercents.last, 1)
    }

    func testManualProgressSliderSnapsOnlyWhenCloseToAnEighth() {
        XCTAssertEqual(ManualProgressSliderPolicy.adjustedPercent(0.13), 0.125, accuracy: 0.000_001)
        XCTAssertEqual(ManualProgressSliderPolicy.adjustedPercent(0.49), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(ManualProgressSliderPolicy.adjustedPercent(0.40), 0.40, accuracy: 0.000_001)
        XCTAssertNil(ManualProgressSliderPolicy.nearbyTickIndex(for: 0.40))
    }

    func testNeonIntensityBuildsFromTwentyPercentToFullCompletion() {
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 20), 0, accuracy: 0.001)
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 40), 0.25, accuracy: 0.001)
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 60), 0.5, accuracy: 0.001)
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 80), 0.75, accuracy: 0.001)
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 100), 1, accuracy: 0.001)
        XCTAssertEqual(DailyMomentumBarStyle.neonIntensity(for: 150), 1, accuracy: 0.001)
    }

    private func point(
        id: String,
        date: Date,
        intentionId: String,
        percent: Double
    ) -> MomentumPoint {
        MomentumPoint(
            id: id,
            date: date,
            intentionId: intentionId,
            intentionTitle: intentionId,
            colorIndex: 0,
            recordingId: id,
            percent: percent,
            timeOffsetSeconds: 0
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
