# Calendar Feature Handoff

## Scope

- Debug-only in-app Calendar experiment.
- Entry point: Insights -> Calendar.
- Reads existing `ExtractedItem.calendarCandidate` data.
- Event-type captures without a usable scheduled date appear under `Needs scheduling` on their recording day; Attune does not claim that recording day is the event date.
- Capture -> Review can add, change, or remove an in-app scheduled date, start time, and optional end time. These edits are stored only in the correction overlay; original AI extraction data is preserved.
- A selected date shows a time-ordered day schedule beneath the month grid.
- New Listening extraction receives the segment recording timestamp and local IANA timezone. `today`, `tomorrow`, and weekdays resolve from that local reference. A recognized clock time without a date uses the recording day.
- A deterministic on-device fallback covers `today`, `tomorrow`, weekdays, AM/PM clock times, noon, and midnight if the provider returns no date.
- Does not import EventKit, request Calendar permission, or write to Apple Calendar.
- Release builds hide the navigation entry through `CalendarFeature.isEnabled`.

## Removal

Fastest rollback: set `CalendarFeature.isEnabled` to `false` in Debug. This hides the Insights entry, Capture schedule card, and Review schedule controls without deleting data.

For full source removal:

1. Remove the `if CalendarFeature.isEnabled { calendarSection }` hook and its two helpers from `LibraryView.swift`.
2. Remove the two `CalendarFeature.isEnabled` schedule blocks and their helpers/state from `InsightDetailView.swift`.
3. Remove `CalendarScheduleCorrection` and `ItemCorrection.calendarSchedule` from `ItemCorrection.swift`.
4. Delete `Pondera/Pondera/UI/Calendar/` and this handoff file.

No recording or transcription migration needs to be reversed. Existing correction JSON safely ignores the removed optional scheduling key. Temporal extraction context can remain independently or be removed from `ExtractorService`, `ExtractionQueue`, `TranscriptionQueue`, and the optional Worker Listening fields.

## Physical iPhone verification

Start a Listening Session and say these phrases clearly:

1. `I have a dentist appointment tomorrow at 2 PM.`
2. `My project review is Friday at 10:30 AM.`
3. `I have a haircut at 4 PM.`
4. `I have a dentist appointment today.`
5. `I should think about calling the dentist sometime.`

Expected results after processing finishes:

- Phrases 1 and 2 appear in Insights and on their interpreted future dates in Insights -> Calendar.
- Phrase 3 appears on the recording day at 4 PM even though no date was spoken.
- Phrase 4 appears on the recording day with `Time not specified`.
- Selecting the appropriate day shows the event title and time in the day schedule.
- Opening a calendar row navigates to the original Capture detail.
- From Capture -> Review, change phrase 1 to a different date and start time, add an end time, save, and confirm the Calendar moves it and shows the edited time range.
- From Review, turn off `Show on Calendar`, save, and confirm the capture returns to `Needs scheduling` rather than staying on the old scheduled date.
- Phrase 5 may remain an intention, but must not appear on the Calendar without an explicit or strongly implied date/time.
- If an event is missing `calendarCandidate.startISO8601`, it appears under `Needs scheduling` on the day it was recorded, with an amber indicator and a Review prompt.
- A dated capture without a supplied clock time shows `Time not specified`; it is not mislabeled as an all-day event.
- Marking a source Capture hidden removes it from the Calendar after reopening or refreshing the screen.
- No Apple Calendar permission prompt appears and no Apple Calendar event is created.

Observable log markers:

- `<STORE> ... CALENDAR view_loaded dated=<count> undated=<count> total=<count> month=<year-month>`
- `<STORE> ... CALENDAR month_changed month=<year-month>`
- `<AI> ... calendar_temporal_resolved session=<id> seg=<index> has_time=<true|false>` when the on-device fallback supplies a missing relative date/time.
- `<AI> ... listening_temporal_contract_fallback session=<id> seg=<index>` while the deployed Worker still uses the older Listening request shape.

## Release gate

Keep the Release flag disabled until the physical test above passes with correct interpreted dates and timezone behavior.

The updated Worker request contract and prompt are implemented and locally tested but have not been deployed by this change. The app remains compatible with the older deployed request shape and retries with reference metadata in `priorContext` until deployment.
