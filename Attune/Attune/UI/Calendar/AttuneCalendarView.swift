//
//  AttuneCalendarView.swift
//  Attune
//
//  Month calendar and selected-day schedule for event-like details captured by
//  Attune. Editing stays in Capture Review; there are no external calendar writes.
//

import SwiftUI

struct AttuneCalendarView: View {
    @State private var items: [ExtractedItem] = []
    @State private var corrections: [String: ItemCorrection] = [:]
    @State private var displayedMonth = Calendar.current.startOfDay(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var captures: [CalendarCapture] {
        CalendarCaptureParser.captures(from: items, corrections: corrections)
    }

    private var selectedCaptures: [CalendarCapture] {
        captures.filter { calendar.isDate($0.start, inSameDayAs: selectedDate) }
    }

    private var undatedCaptures: [CalendarUndatedCapture] {
        CalendarCaptureParser.undatedCaptures(from: items, corrections: corrections)
    }

    private var selectedUndatedCaptures: [CalendarUndatedCapture] {
        undatedCaptures.filter { calendar.isDate($0.capturedAt, inSameDayAs: selectedDate) }
    }

    var body: some View {
        ZStack {
            AttuneScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    monthCard
                    agendaSection
                }
                .padding(.horizontal, AttuneTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .refreshable { loadData() }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") { showToday() }
            }
        }
        .onAppear(perform: loadData)
        .onReceive(NotificationCenter.default.publisher(for: .attuneCorrectionsDidChange)) { _ in
            loadData()
        }
    }

    private var monthCard: some View {
        VStack(spacing: 14) {
            HStack {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                    .foregroundStyle(AttuneTheme.textPrimary)

                Spacer()

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(AttuneTheme.accent)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(for: date)
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }
        }
        .padding(16)
        .attuneCard()
    }

    private func dayButton(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let scheduledCount = captures.lazy.filter { calendar.isDate($0.start, inSameDayAs: date) }.count
        let capturedCount = undatedCaptures.lazy.filter { calendar.isDate($0.capturedAt, inSameDayAs: date) }.count

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? AttuneTheme.background : AttuneTheme.textPrimary)

                HStack(spacing: 3) {
                    Circle()
                        .fill(scheduledCount > 0 ? (isSelected ? AttuneTheme.background : AttuneTheme.accent) : .clear)
                        .frame(width: 5, height: 5)
                    Circle()
                        .fill(capturedCount > 0 ? (isSelected ? AttuneTheme.background.opacity(0.72) : AttuneTheme.warning) : .clear)
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(isSelected ? AttuneTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AttuneTheme.accent.opacity(0.7), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue(dayAccessibilityValue(scheduled: scheduledCount, captured: capturedCount))
    }

    private var agendaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.headline)
                        .foregroundStyle(AttuneTheme.textPrimary)
                    Text(agendaSubtitle)
                        .font(.caption)
                        .foregroundStyle(AttuneTheme.textSecondary)
                }
                Spacer()
            }

            if selectedCaptures.isEmpty && selectedUndatedCaptures.isEmpty {
                emptyAgenda
            } else {
                if !selectedCaptures.isEmpty {
                    agendaGroupHeader(
                        title: "Day schedule",
                        detail: "Events are ordered by their scheduled time.",
                        color: AttuneTheme.accent
                    )

                    ForEach(selectedCaptures) { capture in
                        NavigationLink(destination: InsightDetailView(item: capture.item)) {
                            eventRow(capture)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !selectedUndatedCaptures.isEmpty {
                    agendaGroupHeader(
                        title: "Needs scheduling",
                        detail: "Recorded this day; open Review to choose a date and time.",
                        color: AttuneTheme.warning
                    )

                    ForEach(selectedUndatedCaptures) { capture in
                        NavigationLink(destination: InsightDetailView(item: capture.item)) {
                            undatedEventRow(capture)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var agendaSubtitle: String {
        let total = selectedCaptures.count + selectedUndatedCaptures.count
        if total == 0 { return "No captured events" }
        if selectedUndatedCaptures.isEmpty {
            return "\(selectedCaptures.count) scheduled event\(selectedCaptures.count == 1 ? "" : "s")"
        }
        return "\(selectedCaptures.count) scheduled · \(selectedUndatedCaptures.count) need review"
    }

    private func agendaGroupHeader(title: String, detail: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(AttuneTheme.textSecondary)
            }
        }
        .padding(.top, 4)
    }

    private var emptyAgenda: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AttuneTheme.accent)
            Text("Nothing scheduled from your captures")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AttuneTheme.textPrimary)
            Text("Event-like details with a clear date or time will appear here after Pondera processes what you said.")
                .font(.caption)
                .foregroundStyle(AttuneTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .attuneCard()
    }

    private func eventRow(_ capture: CalendarCapture) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(timeLabel(for: capture))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            .frame(width: 72, alignment: .trailing)

            VStack(spacing: 0) {
                Circle()
                    .fill(AttuneTheme.accent)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(AttuneTheme.accent.opacity(0.28))
                    .frame(width: 2)
            }
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(capture.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)

                Text(eventDetail(for: capture))
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AttuneTheme.textTertiary)
        }
        .padding(14)
        .attuneCard()
    }

    private func undatedEventRow(_ capture: CalendarUndatedCapture) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(AttuneTheme.warning)
                .frame(width: 38, height: 38)
                .background(AttuneTheme.warning.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(capture.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AttuneTheme.textPrimary)
                Text("Choose date & time in Review")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AttuneTheme.warning)
                Text(capture.item.summary.isEmpty ? capture.item.sourceQuote : capture.item.summary)
                    .font(.caption)
                    .foregroundStyle(AttuneTheme.textSecondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AttuneTheme.textTertiary)
        }
        .padding(14)
        .attuneCard()
    }

    private func timeLabel(for capture: CalendarCapture) -> String {
        if capture.isAllDay { return "All day" }
        if !capture.hasSpecifiedTime { return "Time not specified" }
        let start = capture.start.formatted(date: .omitted, time: .shortened)
        guard let end = capture.end,
              calendar.isDate(end, inSameDayAs: capture.start),
              end > capture.start else {
            return start
        }
        return "\(start)–\(end.formatted(date: .omitted, time: .shortened))"
    }

    private func dayAccessibilityValue(scheduled: Int, captured: Int) -> String {
        if scheduled == 0 && captured == 0 { return "No captures" }
        var parts: [String] = []
        if scheduled > 0 { parts.append("\(scheduled) scheduled") }
        if captured > 0 { parts.append("\(captured) need scheduling") }
        return parts.joined(separator: ", ")
    }

    private func eventDetail(for capture: CalendarCapture) -> String {
        if let notes = capture.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            return notes
        }
        return capture.item.summary.isEmpty ? capture.item.sourceQuote : capture.item.summary
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var monthCells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: interval.start) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leadingCount)
        cells.append(contentsOf: dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        })
        let trailingCount = (7 - (cells.count % 7)) % 7
        cells.append(contentsOf: Array(repeating: nil, count: trailingCount))
        return cells
    }

    private func changeMonth(by amount: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: amount, to: displayedMonth),
              let interval = calendar.dateInterval(of: .month, for: nextMonth) else { return }
        displayedMonth = interval.start
        selectedDate = interval.start
        AppLogger.log(AppLogger.STORE, "CALENDAR month_changed month=\(monthLogValue(interval.start))")
    }

    private func showToday() {
        let today = calendar.startOfDay(for: Date())
        selectedDate = today
        displayedMonth = calendar.dateInterval(of: .month, for: today)?.start ?? today
    }

    private func loadData() {
        corrections = CorrectionsStore.shared.loadCorrections()
        items = ExtractionStore.shared.loadAllExtractions()
        AppLogger.log(
            AppLogger.STORE,
            "CALENDAR view_loaded dated=\(captures.count) undated=\(undatedCaptures.count) total=\(items.count) month=\(monthLogValue(displayedMonth))"
        )
    }

    private func monthLogValue(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }
}

#Preview {
    NavigationStack {
        AttuneCalendarView()
    }
}
