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
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    /// Single day button: tappable for past/today, gray + disabled for future
    private func dayButton(for day: WeekDayItem) -> some View {
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)

        return Button(action: {
            if !day.isFutureDay {
                selectedDate = day.date
            }
        }) {
            Text(day.weekdayLetter)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(foregroundColor(day: day, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundColor(day: day, isSelected: isSelected))
                )
        }
        .buttonStyle(.plain)
        .disabled(day.isFutureDay)
    }

    private func foregroundColor(day: WeekDayItem, isSelected: Bool) -> Color {
        if day.isFutureDay {
            return .gray.opacity(0.5)
        }
        if isSelected {
            return .white
        }
        return .gray
    }

    private func backgroundColor(day: WeekDayItem, isSelected: Bool) -> Color {
        if day.isFutureDay {
            return Color.gray.opacity(0.15)
        }
        if isSelected {
            return NeonPalette.neonTeal.opacity(0.5)
        }
        return Color.white.opacity(0.08)
    }
}
