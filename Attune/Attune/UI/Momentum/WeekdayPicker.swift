//
//  WeekdayPicker.swift
//  Attune
//
//  Tabular/segmented weekday selector (M T W T F S S) for Momentum page.
//  Future days shown grayer and unclickable.
//

import SwiftUI

/// One day in the week: date + weekday letter + whether it's a future day
struct WeekDayItem: Identifiable {
    let id: Date
    let date: Date
    let weekdayLetter: String
    let isFutureDay: Bool
}

/// Horizontal row of weekday buttons. Future days are gray and disabled.
struct WeekdayPicker: View {

    /// Days for the current week (Mon–Sun)
    let days: [WeekDayItem]

    /// Currently selected date
    @Binding var selectedDate: Date

    /// Calendar for comparison
    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                dayButton(for: day)
            }
        }
        .padding(.horizontal, 2)
    }

    /// Single day button: tappable for past/today, gray + disabled for future
    private func dayButton(for day: WeekDayItem) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)

        return Button(action: {
            if !day.isFutureDay {
                selectedDate = day.date
            }
        }) {
            VStack(spacing: 3) {
                Text(day.weekdayLetter)
                    .font(.caption2.weight(.semibold))
                Text(day.date.formatted(.dateTime.day()))
                    .font(.caption.monospacedDigit())
                    .fontWeight(isSelected ? .bold : .medium)
            }
                .foregroundColor(foregroundColor(day: day, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor(day: day, isSelected: isSelected))
                )
        }
        .buttonStyle(.plain)
        .disabled(day.isFutureDay)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(day.isFutureDay ? "Unavailable, future date" : (isSelected ? "Selected" : "Available"))
        .accessibilityHint(day.isFutureDay ? "" : "Shows Momentum for this day")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func foregroundColor(day: WeekDayItem, isSelected: Bool) -> Color {
        if day.isFutureDay {
            return AttuneTheme.textTertiary.opacity(0.55)
        }
        if isSelected {
            return AttuneTheme.textPrimary
        }
        return AttuneTheme.textSecondary
    }

    private func backgroundColor(day: WeekDayItem, isSelected: Bool) -> Color {
        if day.isFutureDay {
            return AttuneTheme.surface.opacity(0.5)
        }
        if isSelected {
            return AttuneTheme.accent.opacity(0.28)
        }
        return Color.clear
    }
}
