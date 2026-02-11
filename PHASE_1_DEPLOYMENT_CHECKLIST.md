# Phase 1 - Deployment Checklist

## Pre-Deployment Verification

### Code Quality ✅
- [x] No linter errors in all modified files
- [x] Swift 5 compatibility verified
- [x] All acceptance criteria met
- [x] Comprehensive comments added
- [x] No breaking changes

### Implementation Status ✅
- [x] P1.1: TopicKeyBuilder created and integrated
- [x] P1.2: topicKey used for aggregation
- [x] P1.2b: Collision logging implemented
- [x] P1.3: MainActor concurrency safety
- [x] P1.4: Backward compatibility with migration

### Documentation Status ✅
- [x] TopicKeyBuilder_VERIFICATION.md (P1.1)
- [x] TopicKeyBuilder_P1.2_VERIFICATION.md (P1.2)
- [x] TopicKeyBuilder_P1.3_P1.4_VERIFICATION.md (P1.3 & P1.4)
- [x] IMPLEMENTATION_SUMMARY.md (Technical details)
- [x] PHASE_1_COMPLETE.md (Before/after comparison)
- [x] EXAMPLES_VISUAL.md (Visual examples)
- [x] QUICK_REFERENCE.md (Developer reference)
- [x] PHASE_1_FINAL_SUMMARY.md (Executive summary)

---

## Manual Testing Checklist

### Test 1: Basic Grouping
- [ ] **Setup**: Fresh install or delete Topics.json
- [ ] **Action**: Extract "I need to work out today"
- [ ] **Expected**: New topic created with topicKey="fitness_health|work_out"
- [ ] **Action**: Extract "I should work out tomorrow"
- [ ] **Expected**: Existing topic updated, occurrenceCount=2
- [ ] **Verify**: Log shows `updated=1, created=0`

### Test 2: Category Priority Stability
- [ ] **Action**: Extract item with categories ["work", "fitness_health"]
- [ ] **Expected**: topicKey uses "fitness_health" (higher priority)
- [ ] **Action**: Extract similar item with categories ["fitness_health", "work"]
- [ ] **Expected**: Same topicKey (order doesn't matter)
- [ ] **Verify**: Both items in same topic

### Test 3: Backward Compatibility
- [ ] **Setup**: Replace Topics.json with old version (no topicKey)
- [ ] **Action**: Launch app and check logs
- [ ] **Expected**: See "Topics migrated: added topicKey to legacy topics"
- [ ] **Verify**: Topics.json now has topicKey field
- [ ] **Verify**: All occurrenceCount values preserved
- [ ] **Action**: Restart app
- [ ] **Expected**: No migration message (already done)

### Test 4: Concurrency Safety
- [ ] **Setup**: Enable Swift concurrency checking in Xcode
- [ ] **Action**: Build project
- [ ] **Expected**: No MainActor isolation warnings
- [ ] **Action**: Extract multiple items rapidly
- [ ] **Expected**: No crashes, Topics.json remains consistent

### Test 5: Collision Detection
- [ ] **Action**: Review logs after several extractions
- [ ] **Expected**: If collisions occur, see WARN messages
- [ ] **Verify**: Collision count is low (<5% of updates)
- [ ] **Action**: Review collision messages for patterns

### Test 6: Edge Cases
- [ ] **Test**: Extract item with empty categories
  - [ ] **Expected**: topicKey uses "uncategorized"
- [ ] **Test**: Extract item with unknown categories
  - [ ] **Expected**: topicKey uses alphabetically first
- [ ] **Test**: Submit same item twice
  - [ ] **Expected**: Second submission skipped (no update)

---

## Integration Testing Checklist

### Test 7: Multi-Session Flow
- [ ] **Action**: Record session 1 with multiple mentions of "exercise"
- [ ] **Action**: Wait for transcription and extraction
- [ ] **Verify**: Topics created with topicKey
- [ ] **Action**: Record session 2 with similar mentions
- [ ] **Verify**: Topics updated (not duplicated)
- [ ] **Check**: Topics.json shows increasing occurrenceCount

### Test 8: User Corrections Flow
- [ ] **Action**: Extract item with category "work"
- [ ] **Action**: User corrects category to "fitness_health"
- [ ] **Action**: Extract similar item
- [ ] **Expected**: Uses corrected category in topicKey
- [ ] **Verify**: Different topic created (category changed)

### Test 9: Performance Test
- [ ] **Setup**: Topics.json with 50+ topics
- [ ] **Action**: Extract 10 new items
- [ ] **Measure**: Time to complete
- [ ] **Expected**: < 1 second for all updates
- [ ] **Verify**: No lag in UI

---

## Log Verification Checklist

### Expected Log Patterns

#### Successful Grouping
```
STORE Topics updated created=2 updated=8 skippedIncorrect=1 collisions=0 total=41
```
- [ ] `created` is LOW (few new topics)
- [ ] `updated` is HIGH (most items group)
- [ ] `collisions` is LOW (<5% of total)

#### First Load After Migration
```
STORE Topics migrated: added topicKey to legacy topics count=47
STORE Topics updated created=0 updated=1 total=47
```
- [ ] Migration happens once
- [ ] Count matches existing topics

#### Collision Warning (if occurs)
```
WARN TopicKey collision topicKey="fitness_health|doctor" existingTitle="Doctor Appointment" newTitle="Doctor Strange"
```
- [ ] Review collision for patterns
- [ ] Consider adding more filter words if frequent

---

## Data Integrity Checklist

### Topics.json Validation
- [ ] **Check**: All topics have `topicKey` field
- [ ] **Check**: topicKey format is "category|slug"
- [ ] **Check**: occurrenceCount > 0 for all topics
- [ ] **Check**: itemIds array is not empty
- [ ] **Check**: categories array is sorted and unique
- [ ] **Check**: No duplicate topicKeys (except for collisions)

### Example Valid Topic
```json
{
  "canonicalKey": "work_out__a1b2c3",
  "topicKey": "fitness_health|work_out",
  "displayTitle": "Work Out",
  "occurrenceCount": 3,
  "firstSeenAtISO": "2026-02-01T10:00:00Z",
  "lastSeenAtISO": "2026-02-03T14:30:00Z",
  "categories": ["fitness_health", "personal_growth"],
  "itemIds": ["id1", "id2", "id3"]
}
```

---

## Performance Benchmarks

### Expected Performance
- **Topic lookup**: < 1ms (dictionary O(1))
- **Category selection**: < 0.1ms (~30 comparisons)
- **First load with migration**: +5-10ms (one-time)
- **Subsequent loads**: No overhead
- **Task dispatch**: +0.1ms (negligible)

### Measurement Points
- [ ] Time `loadTopics()` on first launch
- [ ] Time `loadTopics()` on subsequent launches
- [ ] Time `update(with:)` for batch of 10 items
- [ ] Monitor total extraction → topic update latency

---

## Rollback Preparation

### Before Deployment
- [ ] Backup current Topics.json from test device
- [ ] Document current `created` vs `updated` ratio
- [ ] Note current topic count

### Rollback Procedure (if needed)
1. Revert `TopicAggregateStore.swift`:
   ```swift
   let key = topic.canonicalKey  // Instead of topicKey
   ```
2. Remove Task wrapper in `TranscriptionQueue.swift`
3. Redeploy

### Rollback Testing
- [ ] Verify rolled-back version still loads Topics.json
- [ ] Verify no data loss
- [ ] Verify extraction still works

---

## Production Monitoring Plan

### Week 1 Metrics
- [ ] Monitor `created` vs `updated` ratio daily
- [ ] Track collision rate (should be < 5%)
- [ ] Check for migration messages (should be one per device)
- [ ] Look for crashes related to TopicAggregateStore

### Week 2-4 Metrics
- [ ] Topic count growth rate (should stabilize)
- [ ] Average occurrenceCount (should increase)
- [ ] User feedback on duplicate topics (should decrease)

### Alert Thresholds
- **High collision rate** (>10%): Review logs, tune filters
- **Crashes**: Immediate rollback
- **Migration failures**: Investigate permissions/disk space
- **Poor grouping** (`updated` < 40%): Review word filters

---

## Deployment Steps

### Step 1: Pre-Deployment
- [x] All code changes complete
- [x] All documentation complete
- [x] No linter errors
- [ ] Manual testing complete
- [ ] Integration testing complete

### Step 2: TestFlight Deployment
- [ ] Build with release configuration
- [ ] Archive and upload to App Store Connect
- [ ] Deploy to internal testers
- [ ] Monitor crash reports for 3-5 days

### Step 3: Beta Deployment
- [ ] Deploy to external testers (if available)
- [ ] Collect feedback on topic grouping
- [ ] Monitor logs for collision rate
- [ ] Verify migration runs smoothly

### Step 4: Production Deployment
- [ ] Submit to App Store review
- [ ] Prepare release notes mentioning improved topic grouping
- [ ] Monitor first 24 hours closely
- [ ] Be ready for hotfix if needed

---

## Success Criteria (Final Check)

### Code Criteria ✅
- [x] No linter errors
- [x] Swift 5 compatible
- [x] Builds successfully
- [x] All acceptance criteria met

### Functional Criteria
- [ ] Topics group correctly (verified manually)
- [ ] Category order doesn't affect grouping
- [ ] Time/frequency words filtered
- [ ] User corrections respected
- [ ] Collisions logged (if any)

### Safety Criteria
- [ ] No MainActor warnings
- [ ] No crashes during testing
- [ ] Topics.json never corrupted
- [ ] Migration runs successfully

### Performance Criteria
- [ ] No noticeable lag
- [ ] Extraction completes quickly
- [ ] UI remains responsive

---

## Sign-Off

### Development Sign-Off
- [x] Code complete and tested locally
- [x] Documentation complete
- [x] No known issues

### Testing Sign-Off (Required)
- [ ] Manual testing complete
- [ ] Integration testing complete
- [ ] Edge cases verified
- [ ] Performance acceptable

### Deployment Sign-Off (Required)
- [ ] TestFlight deployment successful
- [ ] Beta testing complete (if applicable)
- [ ] Monitoring plan in place
- [ ] Rollback plan documented

---

## Post-Deployment Actions

### Day 1
- [ ] Monitor crash reports
- [ ] Check logs for collision rate
- [ ] Verify migration messages appear once per device
- [ ] Review early user feedback

### Week 1
- [ ] Analyze `created` vs `updated` ratio
- [ ] Check topic count growth
- [ ] Review collision logs
- [ ] Tune word filters if needed

### Month 1
- [ ] Survey users on duplicate topics
- [ ] Analyze long-term topic stability
- [ ] Plan Phase 2 (if collision rate > 10%)

---

## Contact Information

**Documentation**: See `/Users/scott/Programming/Attune/Attune-V4/` for all docs  
**Quick Help**: `QUICK_REFERENCE.md`  
**Complete Details**: `PHASE_1_COMPLETE.md`  
**Testing Guide**: This document

**Status**: Ready for manual testing ✅
