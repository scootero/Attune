# Phases 2, 3, 4 — Implementation Summary

This document summarizes the implementation of Phases 2, 3, and 4 of the topic identity and strength scoring system.

## Phase 2 — Lightweight Normalization (INTENTIONALLY MINIMAL)

### Purpose
Collapse obvious phrasing drift while preserving deterministic identity.

### Files Created/Modified
- **Created:** `NormalizationRules.swift`
- **Modified:** `TopicKeyBuilder.swift`

### What It Does
Applies seed normalization rules (no expansion) in `TopicKeyBuilder` before slug construction:

1. **Phrase replacement** (multi-word) — e.g., "working out" → "workout"
2. **Token normalization** (single-word) — e.g., "exercise" → "workout"
3. **Time/frequency token removal** — e.g., removes "today", "daily", "weekly"
4. **Stopword removal** — Reuses existing stopwords list (no divergent list)

### Seed Rules (Do NOT Expand)
- **9 phrase mappings** (fitness, review, planning)
- **12 token mappings** (fitness, finance, review, mood)
- **Explicit time/frequency token list** (replaces separate timeQualifiers + frequencyWords)

### Result
"work out today" and "start working out daily" → **same topicKey** (`workout` or `start_workout`)

---

## Phase 3 — Strength Scoring (Local, LOW Baseline)

### Purpose
Single occurrences should feel weak. Importance emerges from repetition + decay (later phase).

### Files Created/Modified
- **Created:** `StrengthScorer.swift`
- **Modified:** `ExtractorService.swift` (added strength scoring to pipeline)

### What It Does
Computes per-item strength score based on linguistic intensity patterns:

| Pattern Type | Examples | Score |
|-------------|----------|-------|
| Strong commitment | "must", "need to", "have to", "will" | **0.60** |
| Moderate intent | "want to", "plan to", "going to" | **0.50** |
| Weak/uncertain | "maybe", "might", "consider" | **0.25** |
| Mood-related | "sad", "anxious", "happy", "feeling" | **0.35** |
| Default baseline | (no pattern match) | **0.40** |

### Constraints
- ✅ Clamped to [0.20 – 0.65] range (never exceeds 0.65)
- ✅ Does NOT incorporate occurrence count
- ✅ Does NOT compute topic-level strength
- ✅ Per-item scoring only

### Integration
Added to `ExtractorService` pipeline:
1. Create initial item (AI-generated values)
2. Apply canonicalization (overwrites fingerprint)
3. Apply type classification (overwrites type)
4. **Apply strength scoring** (overwrites AI strength) ← Phase 3
5. Return final item

---

## Phase 4 — Prompt Tuning (Optional, Non-Blocking)

### Purpose
Improve LLM extraction guidance without affecting identity or persistence.

### Files Modified
- **Modified:** `ExtractorService.swift` (updated `buildSystemMessage()`)

### What Changed

#### Confidence Guidance (Clarified)
```
- confidence: how certain you are this extraction is CORRECT (not how important it is)
  → Score based on clarity and certainty of the extraction, not the item's significance
```
**Why:** Prevents conflating confidence (extraction quality) with strength (importance)

#### Strength Guidance (Acknowledged Override)
```
- strength: how important/impactful this item seems (this will be overridden by heuristics)
```
**Why:** Transparent about Phase 3 override; reduces LLM pressure

#### Fingerprint Guidance (Restructured)
```
REQUIRED FINGERPRINT (best-effort concept label):
- fingerprint: a short concept label like "workout" or "call_mom" (your best guess)
  → Do NOT include time qualifiers (today, tomorrow, daily, weekly, etc.)
  → Do NOT attempt semantic grouping or synonym matching
  → Just provide a simple label for this specific mention
```
**Why:** 
- Aligns with Phase 2 (no time qualifiers)
- Prevents LLM from attempting semantic grouping (Phase 2's job)
- Sets expectation as "best-effort hint" (fingerprint is replaced anyway)

### Result
- ✅ Prompt changes do NOT affect topic identity (controlled by TopicKeyBuilder + Canonicalizer)
- ✅ Fingerprint is ignored for grouping (Canonicalizer overwrites it)
- ✅ Changes are optional and non-blocking (system works even if LLM ignores guidance)

---

## Complete Pipeline (After All Phases)

### Extraction Flow
```
1. LLM extracts item with:
   - fingerprint (best-effort label, ignoring time qualifiers)
   - confidence (extraction correctness only)
   - strength (will be overridden)

2. ExtractorService.mapToExtractedItem():
   a. Create initial item (with LLM values)
   b. Canonicalizer.canonicalize() → overwrites fingerprint
   c. TypeClassifier.classify() → overwrites type
   d. StrengthScorer (Phase 3) → overwrites strength
   e. Return final item

3. Topic grouping uses:
   - TopicKeyBuilder (Phase 1) → deterministic topic keys
   - NormalizationRules (Phase 2) → collapses phrasing drift
   - Canonical fingerprint (replaces LLM fingerprint)
```

### What's Deterministic (System-Controlled)
- ✅ Topic identity (TopicKeyBuilder + NormalizationRules)
- ✅ Fingerprints (Canonicalizer)
- ✅ Strength scores (StrengthScorer)
- ✅ Item types (TypeClassifier)

### What's LLM-Generated (Hints Only)
- Title (used as input to deterministic systems)
- Summary (display only)
- Categories (used but not for identity)
- Confidence (preserved from LLM)
- SourceQuote (provenance)

---

## Files Summary

### New Files
- `Attune/Understanding/NormalizationRules.swift` (Phase 2)
- `Attune/Understanding/StrengthScorer.swift` (Phase 3)
- `Attune/docs/phase2_normalization.md` (implied)
- `Attune/docs/phase3_strength_scoring.md`
- `Attune/docs/phase4_prompt_tuning.md`

### Modified Files
- `Attune/Understanding/TopicKeyBuilder.swift` (Phase 2 integration)
- `Attune/Understanding/ExtractorService.swift` (Phase 3 + 4 integration)

### No Linter Errors
All implementations compile successfully with no warnings or errors.

---

## Design Adherence

### Phase 2
✅ Data tuning, not architecture  
✅ Seed rules only (no expansion)  
✅ Did NOT generalize or infer mappings  
✅ Did NOT move normalization into LLM  
✅ Reused stopwords (no divergent list)  

### Phase 3
✅ Single occurrences feel weak (low baseline)  
✅ Strength is per-item only  
✅ Does NOT incorporate occurrence count  
✅ Does NOT compute topic-level strength  
✅ Never exceeds 0.65  

### Phase 4
✅ Prompt tuning does not affect identity  
✅ Prompt changes are optional and non-blocking  
✅ Fingerprint is ignored for grouping  
✅ Changes are guidance-only  

---

## Testing Recommendations

### Phase 2 Test Cases
- "work out today" and "start working out daily" → same topicKey ✓
- "need to exercise" → "need_workout" (token normalization) ✓
- "go over my finances" → "review_finance" (phrase + token) ✓

### Phase 3 Test Cases
- "I must work out" → 0.60 ✓
- "Want to exercise" → 0.50 ✓
- "Maybe I'll work out" → 0.25 ✓
- "Feeling anxious" → 0.35 ✓
- "Work out" → 0.40 (default) ✓

### Phase 4 Test Cases
- LLM fingerprint "workout_today" → Canonicalizer replaces with canonical key ✓
- LLM strength 0.95 → StrengthScorer replaces with heuristic score ≤ 0.65 ✓
- Topic identity remains stable regardless of LLM output variations ✓
