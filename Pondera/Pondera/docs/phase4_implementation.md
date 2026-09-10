# Phase 4 — Curation Implementation Summary

## Overview
Phase 4 implements user corrections as an overlay system, allowing users to mark items as incorrect and edit their categories/type/title without modifying original AI-generated session files.

## Files Created

### 1. Models/ItemCorrection.swift
- Represents user corrections keyed by `itemId` (String, maps to ExtractedItem.id.uuidString)
- Fields:
  - `itemId`: String (UUID.uuidString from ExtractedItem)
  - `isIncorrect`: Bool (explicit flag for marking items incorrect)
  - `correctedTitle`: String? (optional override)
  - `correctedType`: String? (optional override)
  - `correctedCategories`: [String]? (optional override)
  - `note`: String? (optional user note)
  - `updatedAtISO`: String (ISO8601 timestamp)

### 2. Storage/CorrectionsStore.swift
- Manages persistence of corrections to `Documents/Attune/Corrections.json`
- Methods:
  - `loadCorrections()` → [String: ItemCorrection] (dictionary by itemId)
  - `getCorrection(itemId:)` → ItemCorrection? (single lookup)
  - `setCorrection(_:)` (save or update)
  - `deleteCorrection(itemId:)` (remove)
- Uses atomic writes and JSON pretty printing for safety/debuggability

## Files Modified

### 1. Storage/AppPaths.swift
- Added `correctionsFileURL` property pointing to `Documents/Attune/Corrections.json`
- Location: root level, parallel to Sessions/ and Topics/

### 2. Models/ExtractedItem.swift
- Added `CorrectedItemView` struct (view model with overlay applied)
- Added `applyingCorrection(_:)` extension method
- Returns display-ready values (corrected or original) for:
  - `displayTitle`
  - `displayType`
  - `displayCategories`
  - `isMarkedIncorrect`
  - `correctionNote`

### 3. Storage/TopicAggregateStore.swift
- Modified `update(with:)` to apply corrections **on-the-fly** for new items
- Items marked `isIncorrect` are skipped (not added to topics)
- Corrected categories/type are used when building/updating topic aggregates
- No retroactive mutation of Topics.json

### 4. UI/Library/InsightDetailView.swift
- Added correction state loading on appear
- Added `CorrectionsSection` to show applied corrections at top
- Modified `ItemInfoSection` to show corrected vs original values (strikethrough for originals)
- Added "Edit" toolbar button
- Added `CorrectionEditSheet` for editing:
  - Toggle for "Mark as incorrect"
  - TextField for title
  - Picker for type
  - Multi-select toggles for categories
  - TextEditor for note
- Saves/deletes corrections via CorrectionsStore

### 5. UI/Library/InsightsListView.swift
- Loads corrections on appear/refresh
- Passes corrections to `AllItemsView`
- Applies corrections overlay for each item in list
- Shows correction indicators (green pencil for corrected, red X for incorrect)
- Dims items marked as incorrect (50% opacity)

### 6. UI/Library/TopicDetailView.swift
- Loads corrections on appear
- Passes corrections to `OccurrenceRow`
- Shows correction status badges in occurrence rows
- Uses corrected type/categories for display

## Behavior Summary

### On-the-fly Overlay (Phase 4)
- Corrections are applied at **read/render time** only
- No background re-aggregation of Topics.json
- No retroactive mutation of session extraction files
- Original AI values are preserved in session files

### What Gets Corrected
1. **Display**: All UI views show corrected values when correction exists
2. **New Topic Aggregation**: New items use corrected categories when added to topics
3. **Existing Topics**: Not retroactively updated (on-the-fly only for display)

### Items Marked Incorrect
- Shown dimmed (50% opacity) in Insights list
- Skipped when building new topic aggregates
- Still visible in all views (not hidden/deleted)
- Labeled with red "Incorrect" badge

## File Locations
```
Documents/Attune/
├── Sessions/           (unchanged)
├── Extractions/        (unchanged)
├── Topics/             (unchanged)
└── Corrections.json    (new, root level)
```

## Acceptance Criteria ✅
- [x] User can edit an item's categories/type/title and see it persist across launches
- [x] Corrections do not require rewriting old session files
- [x] Topics view and topic detail reflect corrections consistently
- [x] Items marked incorrect are dimmed but remain visible
- [x] Corrections are structured for future training export (JSON format)

## Future Extensibility
The corrections file is structured as a simple JSON array for easy export:
- Can be converted to JSONL for training pipelines
- Contains all original item IDs for traceability
- Timestamps allow temporal analysis of user corrections
- No coupling to internal storage implementation

## Testing Notes
1. Create an item (record → transcribe → extract)
2. Navigate to Insights → All → tap item
3. Tap "Edit" button
4. Try each field:
   - Toggle "Mark as incorrect" → Save → verify dimmed in list
   - Edit title → Save → verify strikethrough + new title shown
   - Change type → Save → verify badge changes
   - Edit categories → Save → verify category list updates
   - Add note → Save → verify note appears in detail view
5. Kill and relaunch app → verify corrections persist
6. Check `Documents/Attune/Corrections.json` exists with proper structure
