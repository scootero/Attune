# Phase 4 — Prompt Tuning Implementation

## Overview
Phase 4 implements optional prompt tuning to improve LLM extraction guidance. These changes are non-blocking and do NOT affect topic identity or persistence (which are controlled by Phase 1 and Phase 2).

## Design Principles
- **Prompt tuning must not affect identity or persistence** — Identity is determined by `TopicKeyBuilder` + `Canonicalizer`, not LLM output
- **Prompt changes are optional and non-blocking** — System still works if LLM ignores guidance
- **Fingerprint is ignored for grouping** — Only used as a hint; canonical fingerprint is computed deterministically

## Implementation

### File: `ExtractorService.swift`
Updated `buildSystemMessage()` to provide clearer guidance on confidence and fingerprints.

### Changes Made

#### 1. Confidence Score Guidance (Clarified)
**Before:**
```
- confidence: how certain you are this extraction is correct
```

**After (Phase 4):**
```
- confidence: how certain you are this extraction is CORRECT (not how important it is)
  → Score based on clarity and certainty of the extraction, not the item's significance
```

**Rationale:** 
- Prevents LLM from conflating confidence (extraction quality) with strength (importance)
- Emphasizes that confidence = correctness only
- Helps ensure high-quality extractions even for "low-importance" items

#### 2. Strength Score Guidance (Acknowledged Override)
**Before:**
```
- strength: how important/impactful this item seems
```

**After (Phase 4):**
```
- strength: how important/impactful this item seems (this will be overridden by heuristics)
```

**Rationale:**
- Transparently acknowledges that strength will be replaced by Phase 3 heuristics
- Reduces pressure on LLM to get strength "right"
- LLM can still provide a value (required by schema), but it won't be used

#### 3. Fingerprint Guidance (Restructured)
**Before:**
```
REQUIRED FINGERPRINT:
- fingerprint: a short stable string derived from the core meaning (for deduplication)
```

**After (Phase 4):**
```
REQUIRED FINGERPRINT (best-effort concept label):
- fingerprint: a short concept label like "workout" or "call_mom" (your best guess)
  → Do NOT include time qualifiers (today, tomorrow, daily, weekly, etc.)
  → Do NOT attempt semantic grouping or synonym matching
  → Just provide a simple label for this specific mention
```

**Rationale:**
- **"best-effort concept label"** — Sets expectation that it's a hint, not authoritative
- **Examples** (`"workout"`, `"call_mom"`) — Shows desired format
- **Do NOT include time qualifiers** — Aligns with Phase 2 normalization (time qualifiers removed from topic keys)
- **Do NOT attempt semantic grouping** — Prevents LLM from trying to match synonyms (that's Phase 2's job)
- **"Just provide a simple label"** — Keeps it lightweight and prevents over-engineering

## Acceptance Criteria

### ✅ Prompt changes do not affect topic identity
- Topic identity is controlled by `TopicKeyBuilder` (which uses `NormalizationRules`)
- LLM fingerprint is ignored for identity/grouping
- Changes are guidance-only, not architectural

### ✅ Fingerprint is ignored for grouping
- `Canonicalizer.canonicalize()` overwrites LLM fingerprint with deterministic key
- Pipeline: LLM fingerprint → **replaced** by canonical fingerprint → used for deduplication
- LLM guidance helps it provide better hints, but has no effect on final behavior

## System Behavior (Before vs After)

### Before Phase 4
- LLM might conflate confidence with importance
- LLM might include "workout_today" and "workout_tomorrow" as different fingerprints
- LLM might try to group "exercise" and "workout" under same fingerprint

### After Phase 4
- LLM understands confidence = extraction quality only
- LLM excludes time qualifiers from fingerprint (e.g., just "workout")
- LLM doesn't attempt semantic grouping (provides simple labels per mention)

### Final Behavior (Both Cases)
- **Identity is still deterministic** — `TopicKeyBuilder` applies Phase 2 normalization rules
- **Fingerprints are still replaced** — `Canonicalizer` generates canonical keys
- **Grouping is still stable** — Based on deterministic keys, not LLM output

## Notes
- These are **hints to the LLM**, not system constraints
- If LLM ignores guidance, the system still works correctly
- Phase 1 (TopicKeyBuilder) and Phase 2 (NormalizationRules) ensure deterministic identity
- Phase 3 (StrengthScorer) ensures deterministic strength values
- LLM output quality can improve, but system doesn't depend on it
