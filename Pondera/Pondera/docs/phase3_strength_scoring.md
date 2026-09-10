# Phase 3 — Strength Scoring Implementation

## Overview
Phase 3 implements local, LOW baseline strength scoring for individual extracted items. Single occurrences feel weak by design. Importance emerges from repetition + decay (to be handled in later phases).

## Design Principles
- **Strength is per-item only** — no topic-level aggregation in v1
- **Heuristic-based** — uses linguistic patterns to assign scores
- **Low baseline** — all scores clamped to [0.20 – 0.65] range
- **Does NOT incorporate occurrence count** — that's for later phases

## Implementation

### File: `StrengthScorer.swift`
Simple heuristic rubric that analyzes title + sourceQuote for linguistic intensity patterns.

### Heuristic Rubric (Priority Order)
1. **Strong commitment** (`must`, `need to`, `have to`, `will`) → **0.60**
2. **Moderate intent** (`want to`, `plan to`, `going to`) → **0.50**
3. **Weak/uncertain** (`maybe`, `might`, `consider`) → **0.25**
4. **Mood-related** (`sad`, `anxious`, `happy`, etc.) → **0.35**
5. **Default baseline** → **0.40**

### Integration Point
Integrated into `ExtractorService.mapToExtractedItem()` pipeline:
1. Create initial item (with AI-generated strength)
2. Apply canonicalization (overwrites fingerprint)
3. Apply type classification (overwrites type)
4. **Apply strength scoring (overwrites AI strength)** ← Phase 3
5. Return final item

## Test Cases (Expected Behavior)

### Strong Commitment (0.60)
- "I must work out today" → 0.60
- "Need to review my finances" → 0.60
- "I have to call mom tomorrow" → 0.60
- "Will start exercising daily" → 0.60

### Moderate Intent (0.50)
- "I want to work out" → 0.50
- "Plan to review finances" → 0.50
- "Going to call mom" → 0.50

### Weak/Uncertain (0.25)
- "Maybe I'll work out" → 0.25
- "Might review my finances" → 0.25
- "Consider calling mom" → 0.25

### Mood-Related (0.35)
- "Feeling sad today" → 0.35
- "I'm anxious about work" → 0.35
- "Happy about the promotion" → 0.35

### Default (0.40)
- "Work out" → 0.40
- "Review finances" → 0.40
- "Call mom" → 0.40

## Constraints Satisfied
✅ Never exceeds 0.65 (all scores ≤ 0.60)  
✅ Does NOT incorporate occurrence count  
✅ Does NOT compute topic-level strength  
✅ Clamped to [0.20 – 0.65] range  
✅ Per-item scoring only  

## Notes
- Patterns are checked in priority order (strongest to weakest)
- First matching pattern determines the score
- Text is lowercased before pattern matching
- Mood patterns aligned with `NormalizationRules.tokenMap` mood tokens
