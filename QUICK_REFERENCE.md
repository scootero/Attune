# Phase 1 Quick Reference Card

## What Changed?

**Before**: Topics grouped by `canonicalKey` (from AI fingerprint)  
**After**: Topics grouped by `topicKey` (deterministic concept key)

## TopicKey Format

```
"primaryCategory|conceptSlug"
```

Example: `"fitness_health|work_out"`

## How It Works

1. **Apply corrections** (if user changed categories)
2. **Select primary category** (from priority list)
3. **Build concept slug** (filter words, take 3-4 tokens)
4. **Generate topicKey** (category + slug)
5. **Lookup/update topic** (by topicKey)

## Word Filtering

Removes 3 types of words:

| Type | Examples |
|------|----------|
| **Stopwords** | a, the, is, are, have, do, will, i, me, you |
| **Time** | today, tomorrow, monday, week, month, next, last |
| **Frequency** | daily, weekly, monthly, always, often, again |

## Category Priority

Checked in order (first match wins):

1. fitness_health
2. health
3. nutrition
4. career
5. work
6. money_finance
7. relationships_social
8. family
9. learning
10. growth
11. peace_wellbeing
12. mental_health
13. uncategorized

## Key Behaviors

✅ **Same concept → Same topicKey → Updates existing topic**  
✅ **Category order irrelevant** (priority list decides)  
✅ **Time/frequency ignored** (filtered out)  
✅ **Corrections applied first** (affects topicKey)  
✅ **Collisions logged** (but still merged)

## Log Format

```
STORE Topics updated created=X updated=Y skippedIncorrect=Z collisions=W total=N
```

- `created`: New topics created
- `updated`: Existing topics updated
- `skippedIncorrect`: Items marked wrong by user
- `collisions`: TopicKey collisions detected
- `total`: Total topics in database

## Collision Warning

```
WARN TopicKey collision topicKey="..." existingTitle="..." newTitle="..."
```

Means: Two different concepts got same topicKey (rare, needs tuning)

## Files Modified

| File | Change |
|------|--------|
| `Understanding/TopicKeyBuilder.swift` | NEW (252 lines) |
| `Models/TopicAggregate.swift` | +5 lines (added topicKey field) |
| `Storage/TopicAggregateStore.swift` | ~60 lines (use topicKey for lookups) |

## API Changes

### New Functions

```swift
// Select primary category deterministically
TopicKeyBuilder.selectPrimaryCategory(from: [String]) -> String

// Generate topic key
TopicKeyBuilder.makeTopicKey(item: ExtractedItem, primaryCategory: String) -> String
```

### Modified Behavior

```swift
// OLD: Indexed by canonicalKey
var topics: [String: TopicAggregate] 

// NEW: Indexed by topicKey (with canonicalKey fallback)
let key = topic.topicKey ?? topic.canonicalKey
topics[key] = topic
```

## Testing Checklist

- [ ] Same concept twice → `updated=1`
- [ ] Different category order → Same topicKey
- [ ] Time words filtered → Same topicKey
- [ ] User correction → Different topicKey
- [ ] Check Topics.json for topicKey field
- [ ] Check logs for collision count

## Troubleshooting

**Q: Topics not grouping?**  
A: Check log for `updated=0`. Review topicKey values in Topics.json. Ensure time/freq words are filtered.

**Q: Too many collisions?**  
A: Review WARN logs. Add more words to filter lists. Consider increasing token count (3-4 → 4-5).

**Q: Wrong category selected?**  
A: Check priority list. Category with highest priority always wins. Use user corrections to override.

**Q: Topics.json corrupted?**  
A: Check for `Topics.corrupt.<timestamp>.json` backup. System auto-renames and starts fresh.

## Backward Compatibility

- Old topics without `topicKey` still load (use canonicalKey fallback)
- No data migration needed
- System self-heals as new items arrive
- Can rollback by reverting code (data preserved)

## Success Metrics

**Good**:
- `updated / (created + updated)` > 0.6 (60% updates)
- `collisions` < 5% of total updates
- Topic count stabilizes over time

**Bad**:
- `created` keeps growing linearly
- `updated` stays near zero
- High collision rate (>10%)

## Code Locations

```
Attune/Attune/
├── Understanding/
│   └── TopicKeyBuilder.swift          ← Core logic
├── Models/
│   └── TopicAggregate.swift           ← Data model
└── Storage/
    └── TopicAggregateStore.swift      ← Persistence
```

## Next Steps After Deployment

1. Deploy to production
2. Monitor logs for 1 week
3. Check `created` vs `updated` ratio
4. Review collision logs
5. Tune word filters if needed
6. Collect user feedback

## Emergency Rollback

If needed, revert only `TopicAggregateStore.swift`:

```swift
// Change this:
let key = topic.topicKey ?? topic.canonicalKey

// Back to this:
let key = topic.canonicalKey
```

Data is preserved. Can re-enable later.

## Support

- Docs: `PHASE_1_COMPLETE.md`
- Examples: `EXAMPLES_VISUAL.md`
- Technical: `IMPLEMENTATION_SUMMARY.md`
- Tests: `TopicKeyBuilder_P1.2_VERIFICATION.md`
