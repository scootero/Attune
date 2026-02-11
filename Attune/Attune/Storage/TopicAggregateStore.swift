//
//  TopicAggregateStore.swift
//  Attune
//
//  Manages persistence of TopicAggregate objects to/from a single JSON file.
//  Handles incremental updates without scanning all session extraction files.
//  Topics are indexed by canonical key for efficient lookups and updates.
//

import Foundation

/// Manages loading and saving of TopicAggregate objects to disk using JSON.
/// All topics are stored in a single file: Documents/Attune/Topics/Topics.json
/// File format: [TopicAggregate] (array, for simplicity)
@MainActor
final class TopicAggregateStore {
    
    // MARK: - Initialization
    
    /// Shared singleton instance
    static let shared = TopicAggregateStore()
    
    private init() {
        // Ensure directories exist on initialization
        try? AppPaths.ensureDirectoriesExist()
    }
    
    // MARK: - Loading
    
    /// Loads all topic aggregates from disk
    /// Returns dictionary indexed by topicKey for efficient lookups (Phase 1.2)
    /// P1.4: Migrates legacy topics without topicKey on first load (atomic, one-time)
    /// - Returns: Dictionary mapping topicKeys to topic aggregates
    func loadTopics() -> [String: TopicAggregate] {
        let fileURL = AppPaths.topicsFileURL
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        
        // Load and decode
        guard let data = try? Data(contentsOf: fileURL) else {
            AppLogger.log(AppLogger.ERR, "Topics load failed error=\"Failed to read file\"")
            return [:]
        }
        
        // Configure decoder
        let decoder = JSONDecoder()
        
        guard var topicsArray = try? decoder.decode([TopicAggregate].self, from: data) else {
            // Corruption detected - handle gracefully
            handleCorruptedFile(fileURL: fileURL)
            return [:]
        }
        
        // P1.4: Migrate legacy topics without topicKey (one-time, atomic)
        var needsMigration = false
        var migratedTopics: [TopicAggregate] = []
        
        for topic in topicsArray {
            if topic.topicKey == nil {
                needsMigration = true
                
                // Derive topicKey from existing data
                // Use first category as primary (simple fallback for legacy data)
                let primaryCategory = topic.categories.first ?? "uncategorized"
                
                // Extract stem from canonicalKey (format: "stem__hash")
                let stem = extractStem(from: topic.canonicalKey)
                
                // Build fallback topicKey: "category|stem"
                let fallbackTopicKey = "\(primaryCategory)|\(stem)"
                
                // Create new topic with all fields preserved plus topicKey
                var migratedTopic = TopicAggregate(
                    canonicalKey: topic.canonicalKey,
                    displayTitle: topic.displayTitle,
                    firstSeenAtISO: topic.firstSeenAtISO,
                    categories: topic.categories,
                    itemId: topic.itemIds.first ?? "",  // Just for init, will overwrite
                    topicKey: fallbackTopicKey
                )
                
                // Restore original mutable fields
                migratedTopic.occurrenceCount = topic.occurrenceCount
                migratedTopic.lastSeenAtISO = topic.lastSeenAtISO
                migratedTopic.itemIds = topic.itemIds
                
                migratedTopics.append(migratedTopic)
            } else {
                // Already has topicKey, keep as-is
                migratedTopics.append(topic)
            }
        }
        
        // Save migrated topics atomically (one-time operation)
        if needsMigration {
            do {
                try saveTopicsArray(migratedTopics)
                AppLogger.log(
                    AppLogger.STORE,
                    "Topics migrated: added topicKey to legacy topics count=\(migratedTopics.count)"
                )
            } catch {
                AppLogger.log(
                    AppLogger.ERR,
                    "Topics migration failed error=\"\(error.localizedDescription)\""
                )
                // Continue with migration in-memory even if save fails
            }
            topicsArray = migratedTopics
        }
        
        // Convert array to dictionary indexed by topicKey (Phase 1.2)
        // After migration, all topics have topicKey
        var topicsDict: [String: TopicAggregate] = [:]
        for topic in topicsArray {
            let key = topic.topicKey ?? topic.canonicalKey  // Fallback for safety
            topicsDict[key] = topic
        }
        
        return topicsDict
    }
    
    /// Handles a corrupted Topics.json file by renaming and starting fresh
    /// - Parameter fileURL: URL of the corrupted file
    private func handleCorruptedFile(fileURL: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let corruptedURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Topics.corrupt.\(timestamp).json")
        
        do {
            // Rename corrupted file
            try FileManager.default.moveItem(at: fileURL, to: corruptedURL)
            AppLogger.log(
                AppLogger.ERR,
                "Topics corrupted - renamed to \(corruptedURL.lastPathComponent), starting fresh"
            )
        } catch {
            // If rename fails, just log and continue (file will be overwritten)
            AppLogger.log(
                AppLogger.ERR,
                "Topics corrupted - failed to rename, will overwrite: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Updating
    
    /// Updates topic aggregates with newly extracted items (incremental, no session scanning)
    /// This should be called after ExtractionStore.appendItems succeeds
    /// Phase 1.2: Uses topicKey (not canonicalKey) for aggregation
    /// Applies user corrections overlay when building/updating topics (for new items only)
    /// - Parameter items: Array of newly extracted items (already canonicalized)
    func update(with items: [ExtractedItem]) {
        // Skip empty batches
        guard !items.isEmpty else { return }
        
        // Load existing topics and corrections
        var topics = loadTopics()
        let corrections = CorrectionsStore.shared.loadCorrections()
        
        // Track stats for logging
        var created = 0
        var updated = 0
        var skippedIncorrect = 0
        var collisions = 0
        
        // Process each item
        for item in items {
            // Apply corrections overlay BEFORE computing topicKey
            let correction = corrections[item.id]
            let correctedView = item.applyingCorrection(correction)
            
            // Skip items marked as incorrect (don't add to topics)
            if correctedView.isMarkedIncorrect {
                skippedIncorrect += 1
                continue
            }
            
            // Use corrected categories for topic aggregation
            let effectiveCategories = correctedView.displayCategories
            
            // Select stable primary category using priority list
            let primaryCategory = TopicKeyBuilder.selectPrimaryCategory(from: effectiveCategories)
            
            // Generate topicKey using corrected data
            let topicKey = TopicKeyBuilder.makeTopicKey(
                item: item,
                primaryCategory: primaryCategory
            )
            
            // canonicalKey kept for backward compatibility only
            let canonicalKey = item.fingerprint
            
            // Check if topic already exists using topicKey
            if var existingTopic = topics[topicKey] {
                // Topic exists - check for collision (P1.2b)
                // Collision = topicKey matches but item is not already in the topic
                if !existingTopic.itemIds.contains(item.id) {
                    // Check if this is a genuine collision (different concept, same key)
                    // For now, we just log and proceed with the merge
                    if existingTopic.canonicalKey != canonicalKey {
                        // Different canonicalKey = potential collision
                        collisions += 1
                        AppLogger.log(
                            AppLogger.ERR,
                            "TopicKey collision topicKey=\"\(topicKey)\" existingTitle=\"\(existingTopic.displayTitle)\" newTitle=\"\(correctedView.displayTitle)\""
                        )
                    }
                    
                    // Add new mention with corrected categories
                    // NOTE: addMention will merge categories, but we preserve the topic's primary category
                    // by not overwriting the categories array entirely (just union merge in addMention)
                    var correctedItem = item
                    if correction?.correctedCategories != nil {
                        // Create a temporary modified item for addMention
                        correctedItem = ExtractedItem(
                            id: item.id,
                            sessionId: item.sessionId,
                            segmentId: item.segmentId,
                            segmentIndex: item.segmentIndex,
                            type: correctedView.displayType,
                            title: correctedView.displayTitle,
                            summary: item.summary,
                            categories: effectiveCategories,
                            confidence: item.confidence,
                            strength: item.strength,
                            sourceQuote: item.sourceQuote,
                            contextBefore: item.contextBefore,
                            contextAfter: item.contextAfter,
                            fingerprint: item.fingerprint,
                            reviewState: item.reviewState,
                            reviewedAt: item.reviewedAt,
                            calendarCandidate: item.calendarCandidate,
                            createdAt: item.createdAt,
                            extractedAt: item.extractedAt
                        )
                    }
                    
                    existingTopic.addMention(from: correctedItem)
                    topics[topicKey] = existingTopic
                    updated += 1
                    
                    // Log matched existing topic (for verification)
                    AppLogger.log(
                        AppLogger.STORE,
                        "[TopicKey] rawTitle=\"\(item.title)\" canonicalTitle=\"\(existingTopic.displayTitle)\" topicKey=\"\(topicKey)\" action=matchedExisting occurrenceCount=\(existingTopic.occurrenceCount)"
                    )
                } else {
                    // Item already tracked in this topic - this is a duplicate submission
                    // Just skip it (no update needed)
                }
            } else {
                // New topic - create aggregate with corrected categories
                let stem = extractStem(from: canonicalKey)
                // Prefer AI title, fallback to stem title-case
                let displayTitle = Canonicalizer.generateCanonicalTitle(from: stem, aiTitle: correctedView.displayTitle)
                
                let newTopic = TopicAggregate(
                    canonicalKey: canonicalKey,
                    displayTitle: displayTitle,
                    firstSeenAtISO: item.createdAt,
                    categories: effectiveCategories,
                    itemId: item.id,
                    topicKey: topicKey
                )
                
                topics[topicKey] = newTopic
                created += 1
                
                // Log new topic creation (for verification)
                AppLogger.log(
                    AppLogger.STORE,
                    "[TopicKey] rawTitle=\"\(item.title)\" canonicalTitle=\"\(displayTitle)\" topicKey=\"\(topicKey)\" action=created categories=\"\(effectiveCategories.joined(separator: ","))\""
                )
            }
        }
        
        // Save updated topics
        do {
            try saveTopics(topics)
            let logMsg = "Topics updated created=\(created) updated=\(updated) skippedIncorrect=\(skippedIncorrect) collisions=\(collisions) total=\(topics.count)"
            AppLogger.log(AppLogger.STORE, logMsg)
        } catch {
            AppLogger.log(
                AppLogger.ERR,
                "Topics save failed error=\"\(error.localizedDescription)\""
            )
        }
    }
    
    // MARK: - Private Helpers
    
    /// Saves topics dictionary to disk as JSON array
    /// - Parameter topics: Dictionary of topics indexed by canonical key
    private func saveTopics(_ topics: [String: TopicAggregate]) throws {
        let topicsArray = Array(topics.values)
        try saveTopicsArray(topicsArray)
    }
    
    /// Saves topics array to disk as JSON (P1.4: used for migration)
    /// - Parameter topicsArray: Array of topic aggregates
    private func saveTopicsArray(_ topicsArray: [TopicAggregate]) throws {
        let fileURL = AppPaths.topicsFileURL
        
        // Encode to JSON with pretty printing for readability
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(topicsArray)
        
        // Atomic write to prevent corruption
        try data.write(to: fileURL, options: .atomic)
    }
    
    /// Extracts the topic stem from a canonical key
    /// Format: "<stem>__<hash>" -> returns "<stem>"
    /// - Parameter canonicalKey: Full canonical key with hash suffix
    /// - Returns: Topic stem without hash
    private func extractStem(from canonicalKey: String) -> String {
        // Split by "__" and take first component
        let components = canonicalKey.components(separatedBy: "__")
        return components.first ?? canonicalKey
    }
}
