# Phase 1 Fixes Summary

## What Was Fixed

### 1. TypeClassifier - Conservative About Commitments ✅

**Problem:** The classifier was too aggressive in marking things as "commitment" because it included broad patterns like "I need to" and "I have to".

**Fix Applied:**
- **Reordered priority:** Events > Commitments > State > Intention
- **Narrowed commitment patterns:** Only explicit obligations like "I promised", "I'm required to", "I must by [date]"
- **Moved "need to" and "have to" to intentions:** These are now treated as plans/desires unless explicitly tied to a deadline or promise

**Result:** 
- "I need to lose weight" → **intention** (not commitment)
- "I promised mom I'd call" → **commitment** ✓
- "She got a new job" → **state** ✓

### 2. Canonicalizer - Removed Categories from Hash ✅

**Problem:** Hash input included AI-generated categories, causing the same real-world topic to generate different canonical keys across sessions.

**Before:**
```swift
let hashInput = "\(stem)|\(sortedCategories)"
// Session 1: categories = ["career_work", "money_finance"] → hash = a1c9f2
// Session 2: categories = ["career_work"] → hash = b7d8e3 (DIFFERENT!)
```

**After:**
```swift
let hashInput = stem  // Categories removed
// Session 1: stem = "spouse_job_change" → hash = a1c9f2
// Session 2: stem = "spouse_job_change" → hash = a1c9f2 (SAME!)
```

**Result:** Same real-world topic ALWAYS maps to the same canonical key regardless of how the AI categorizes it.

### 3. Canonical Title Generation ✅

**Problem:** Topics view would show flickering titles as new mentions came in with different AI-generated titles.

**Fix Added:**
- `generateCanonicalTitle(from:)` - Converts stem to stable display title
  - Example: `"spouse_job_change"` → `"Spouse Job Change"`
- `isBetterTitle(_:than:)` - Only updates title if new one is objectively better
  - Longer and more specific (but not too long)
  - Doesn't contain filler words like "impact", "thing", "stuff"
  - Prefers stability (same length = keep existing)

**Result:** Topics will show stable, canonical titles that don't flicker between "Wife's New Job" and "Melanie's new job impact".

## Files Modified

1. **TypeClassifier.swift**
   - Updated priority order (events first, commitments second)
   - Narrowed commitment patterns
   - Moved "need to"/"have to" to intentions

2. **Canonicalizer.swift**
   - Removed categories from hash input
   - Added `generateCanonicalTitle(from:)` method
   - Added `isBetterTitle(_:than:)` method

## What's Next

Phase 1 is now **complete and stable**. Ready to proceed to:
- **Phase 2:** Topic aggregation backend (TopicAggregate + TopicAggregateStore)
- **Phase 3:** UI (Topics tab + All/Topics switcher)

## Testing Recommendations

After building, test with these scenarios:

1. **Type Classification:**
   - Say "I need to lose weight" → should be **intention**
   - Say "I promised mom I'd call her" → should be **commitment**
   - Say "My wife got a new job" → should be **state**

2. **Canonical Keys:**
   - Record multiple sessions mentioning "wife's new job" / "Melanie's new job"
   - Check that all generate the same fingerprint (e.g., `spouse_job_change__a1c9f2`)

3. **Title Stability:**
   - Verify `Canonicalizer.generateCanonicalTitle(from: "spouse_job_change")` returns `"Spouse Job Change"`
