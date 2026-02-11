# Phase 1 Visual Examples

## Example 1: Basic Grouping (Time-Invariant)

### Session 1: Monday Morning
```
User says: "I need to work out today"

AI extracts:
{
  "title": "work out today",
  "categories": ["fitness_health"],
  "sourceQuote": "I need to work out today"
}

Processing:
1. Apply corrections: none
2. Select primary category: "fitness_health" (from priority list)
3. Build concept slug:
   - Input: "work out today I need to work out today"
   - Lowercase: "work out today i need to work out today"
   - Remove stopwords: "work out today need work out today"
   - Remove time words: "work out ~~today~~ need work out ~~today~~"
   - Take 3-4 tokens: "work_out"
4. Generate topicKey: "fitness_health|work_out"

Result: NEW TOPIC CREATED
topicKey: "fitness_health|work_out"
displayTitle: "Work Out"
occurrenceCount: 1
```

### Session 2: Tuesday Evening
```
User says: "I should start working out daily"

AI extracts:
{
  "title": "start working out daily",
  "categories": ["fitness_health", "personal_growth"],
  "sourceQuote": "I should start working out daily"
}

Processing:
1. Apply corrections: none
2. Select primary category: "fitness_health" (higher priority than personal_growth)
3. Build concept slug:
   - Input: "start working out daily I should start working out daily"
   - Lowercase: "start working out daily i should start working out daily"
   - Remove stopwords: "start working out daily should start working out daily"
   - Remove frequency words: "start working out ~~daily~~ should start working out ~~daily~~"
   - Take 3-4 tokens: "start_work_out"
4. Generate topicKey: "fitness_health|start_work_out"

WAIT... Different topicKey! ("work_out" vs "start_work_out")

Actually, let me recalculate more carefully:
- "work out" → tokens: ["work", "out"]
- "start working out" → tokens: ["start", "working", "out"]
- After filtering "out" (short word): ["work"] vs ["start", "working"]

Hmm, this reveals "working" vs "work" difference.
Let me check the stopwords list...
"working" is NOT in the stopword list (only "work" as verb form).

So actually:
- Session 1: "work_out" 
- Session 2: "start_working_out"

These would be DIFFERENT topics!

To make them same, we need to ensure verb forms are normalized or filtered.
```

**Note**: This example reveals a limitation - verb forms (work/working) need handling.

Let me show a clearer example:

## Example 2: Same Concept, Different Phrasing

### Session 1
```
User says: "I have a doctor appointment tomorrow"

AI extracts:
{
  "title": "doctor appointment",
  "categories": ["fitness_health"],
  "sourceQuote": "I have a doctor appointment tomorrow"
}

Processing:
1. Concept slug from "doctor appointment I have a doctor appointment tomorrow":
   - Tokens: ["doctor", "appointment", "have", "doctor", "appointment", "tomorrow"]
   - Filter stopwords: ["doctor", "appointment", "doctor", "appointment"]
   - Remove duplicates & take 3-4: "doctor_appointment"
2. Primary category: "fitness_health"
3. TopicKey: "fitness_health|doctor_appointment"

Result: NEW TOPIC
occurrenceCount: 1
```

### Session 2
```
User says: "I have my doctor appointment next week"

AI extracts:
{
  "title": "doctor appointment next week",
  "categories": ["fitness_health"],
  "sourceQuote": "I have my doctor appointment next week"
}

Processing:
1. Concept slug from "doctor appointment next week I have my doctor appointment next week":
   - Tokens: ["doctor", "appointment", "next", "week", "have", "doctor", "appointment", ...]
   - Filter stopwords: ["doctor", "appointment", "next", "week", "doctor", "appointment"]
   - Filter time words: ["doctor", "appointment", ~~"next"~~, ~~"week"~~, ...]
   - Take 3-4: "doctor_appointment"
2. Primary category: "fitness_health"
3. TopicKey: "fitness_health|doctor_appointment"

Result: EXISTING TOPIC FOUND! ✅
occurrenceCount: 2 (incremented)
Log: "Topics updated created=0 updated=1"
```

## Example 3: Category Priority Stability

### Scenario A: Categories in Order [fitness_health, career]
```
User says: "I want to exercise during lunch break"

AI extracts:
{
  "title": "exercise during lunch",
  "categories": ["fitness_health", "career"],  // fitness first
  "sourceQuote": "I want to exercise during lunch break"
}

Processing:
1. Select primary category:
   - Check priority list...
   - "fitness_health" found at position 0 ✅
   - Return: "fitness_health"
2. Concept slug: "exercise_lunch"
3. TopicKey: "fitness_health|exercise_lunch"
```

### Scenario B: Categories Reversed [career, fitness_health]
```
Same user says same thing, but AI returns categories in different order:

AI extracts:
{
  "title": "exercise during lunch",
  "categories": ["career", "fitness_health"],  // career first
  "sourceQuote": "I want to exercise during lunch break"
}

Processing:
1. Select primary category:
   - Check priority list...
   - "fitness_health" found at position 0 ✅ (checked before "career")
   - Return: "fitness_health" (SAME AS SCENARIO A!)
2. Concept slug: "exercise_lunch"
3. TopicKey: "fitness_health|exercise_lunch" ✅ SAME!

Result: SAME TOPIC regardless of category order!
```

## Example 4: User Corrections Change Grouping

### Initial Extraction
```
User says: "I need to finish the project report"

AI extracts:
{
  "title": "finish project report",
  "categories": ["career"],
  "sourceQuote": "I need to finish the project report"
}

Processing:
1. Primary category: "career"
2. Concept slug: "finish_project_report"
3. TopicKey: "career|finish_project_report"

Result: NEW TOPIC in career category
```

### User Corrects Category
```
User thinks: "This is actually about learning, not career"
User corrects: categories → ["learning"]

Next similar extraction (different session):
{
  "title": "project report deadline",
  "categories": ["career"],  // AI still says career
  "sourceQuote": "project report deadline is coming up"
}

But user has correction stored for this pattern!

Processing:
1. Apply correction: categories → ["learning"]
2. Primary category: "learning" (corrected!)
3. Concept slug: "project_report_deadline"
4. TopicKey: "learning|project_report_deadline"

Result: Different topic! (learning, not career)
```

## Example 5: Collision Detection

### Session 1
```
User says: "I need to see the doctor about my knee"

AI extracts:
{
  "title": "see doctor about knee",
  "categories": ["fitness_health"]
}

Processing:
TopicKey: "fitness_health|doctor_knee"
CanonicalKey: "doctor_knee__a1b2c3"

Result: NEW TOPIC
```

### Session 2 (Different Context)
```
User says: "watching Doctor Who tonight"

AI extracts (incorrectly):
{
  "title": "watching doctor tonight",
  "categories": ["fitness_health"]  // Wrong category!
}

Processing:
TopicKey: "fitness_health|watching_doctor"
CanonicalKey: "watching_doctor_tonight__x9y8z7"

Result: NEW TOPIC (different slug, no collision)
```

But if slug was same:
```
TopicKey: "fitness_health|doctor_knee"  // Same as Session 1!
CanonicalKey: "doctor_who_watching__x9y8z7"  // Different!

Collision detected! ⚠️
Log: WARN TopicKey collision topicKey="fitness_health|doctor_knee" 
     existingTitle="Doctor Knee" newTitle="Watching Doctor"

Result: Items MERGED anyway (conservative)
User can review logs and fix AI categorization
```

## Example 6: Complete Flow Diagram

```
┌─────────────────────┐
│ User speaks:        │
│ "work out tomorrow" │
└──────────┬──────────┘
           │
           ▼
┌─────────────────────────────┐
│ AI Extraction               │
├─────────────────────────────┤
│ title: "work out tomorrow"  │
│ categories: ["fitness_..."] │
│ fingerprint: (AI generated) │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────┐
│ Canonicalizer               │
│ (Phase 0 - Unchanged)       │
├─────────────────────────────┤
│ fingerprint → canonicalKey  │
│ "work_out__a1b2c3"          │
└──────────┬──────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Apply Corrections (Phase 1.2)       │
├─────────────────────────────────────┤
│ Check if user corrected categories  │
│ effectiveCategories = corrected or  │
│                       original      │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Select Primary Category (Phase 1.2) │
├─────────────────────────────────────┤
│ TopicKeyBuilder.selectPrimary(...)  │
│ → "fitness_health" (priority 0)     │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Build Concept Slug (Phase 1.1)      │
├─────────────────────────────────────┤
│ Input: "work out tomorrow..."       │
│ Filter stopwords: "work out..."     │
│ Filter time: "work out ~~tomorrow~~"│
│ Tokens: ["work", "out"]             │
│ Slug: "work_out"                    │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Generate TopicKey (Phase 1.1)       │
├─────────────────────────────────────┤
│ topicKey = category + "|" + slug    │
│ "fitness_health|work_out"           │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Lookup Topic (Phase 1.2)            │
├─────────────────────────────────────┤
│ topics[topicKey]                    │
│   - Found? → Update (updated++)     │
│   - Not found? → Create (created++) │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ Save Topics.json                    │
├─────────────────────────────────────┤
│ [{                                  │
│   "canonicalKey": "work_out__a1..", │
│   "topicKey": "fitness_health|...", │
│   "displayTitle": "Work Out",       │
│   "occurrenceCount": 2,             │
│   "itemIds": ["id1", "id2"]         │
│ }]                                  │
└─────────────────────────────────────┘
```

## Log Examples

### First Extraction (Creates Topic)
```
STORE Topics updated created=1 updated=0 skippedIncorrect=0 collisions=0 total=1
```

### Second Extraction (Same Concept)
```
STORE Topics updated created=0 updated=1 skippedIncorrect=0 collisions=0 total=1
```

### Batch with Mixed Results
```
STORE Topics updated created=2 updated=5 skippedIncorrect=1 collisions=0 total=48
```
- 2 new topics created
- 5 existing topics updated
- 1 item marked incorrect (skipped)
- 0 collisions detected
- 48 total topics in database

### Collision Detected
```
STORE Topics updated created=1 updated=3 skippedIncorrect=0 collisions=1 total=49
WARN TopicKey collision topicKey="fitness_health|doctor" existingTitle="Doctor Appointment" newTitle="Doctor Strange"
```

## Topics.json Example

```json
[
  {
    "canonicalKey": "work_out__a1b2c3",
    "topicKey": "fitness_health|work_out",
    "displayTitle": "Work Out",
    "occurrenceCount": 3,
    "firstSeenAtISO": "2026-02-01T10:00:00Z",
    "lastSeenAtISO": "2026-02-03T14:30:00Z",
    "categories": ["fitness_health", "personal_growth"],
    "itemIds": ["item-1", "item-2", "item-3"]
  },
  {
    "canonicalKey": "doctor_appointment__x9y8z7",
    "topicKey": "fitness_health|doctor_appointment",
    "displayTitle": "Doctor Appointment",
    "occurrenceCount": 2,
    "firstSeenAtISO": "2026-02-02T09:00:00Z",
    "lastSeenAtISO": "2026-02-03T09:00:00Z",
    "categories": ["fitness_health"],
    "itemIds": ["item-4", "item-5"]
  },
  {
    "canonicalKey": "project_deadline__m5n6o7",
    "topicKey": "career|project_deadline",
    "displayTitle": "Project Deadline",
    "occurrenceCount": 1,
    "firstSeenAtISO": "2026-02-03T15:00:00Z",
    "lastSeenAtISO": "2026-02-03T15:00:00Z",
    "categories": ["career"],
    "itemIds": ["item-6"]
  }
]
```

## Summary

✅ **Time-invariant**: "today" vs "tomorrow" → same topic  
✅ **Frequency-invariant**: "daily" vs "weekly" → same topic  
✅ **Category-stable**: Order doesn't matter → same topic  
✅ **Correction-aware**: User corrections affect grouping  
✅ **Collision-visible**: Logs show when keys collide  
✅ **Simple**: No ML, no embeddings, just word filtering  
