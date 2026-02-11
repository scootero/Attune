//
//  ItemResolver.swift
//  Attune
//
//  Helper for efficiently resolving ExtractedItem IDs to full items.
//  Uses session-batched loading to minimize file I/O when resolving multiple items.
//

import Foundation

/// Helper for resolving item IDs to full ExtractedItem instances
/// Designed for efficient batch resolution by loading each session file only once
struct ItemResolver {
    
    // MARK: - Public API
    
    /// Resolves an array of item IDs to their full ExtractedItem instances
    /// Uses session-batched loading for efficiency: each session file is loaded at most once
    /// Orphaned IDs (items not found in session files) are silently skipped with light logging
    /// - Parameter itemIds: Array of item IDs to resolve
    /// - Returns: Array of resolved items (may be smaller than input if some IDs are orphaned)
    static func resolveItems(itemIds: [String]) -> [ExtractedItem] {
        // Early return for empty input
        guard !itemIds.isEmpty else {
            return []
        }
        
        // Load all extractions across all sessions (flattened)
        let allItems = ExtractionStore.shared.loadAllExtractions()
        
        // Build lookup dictionary for O(1) access
        var itemsById: [String: ExtractedItem] = [:]
        for item in allItems {
            itemsById[item.id] = item
        }
        
        // Resolve each ID, tracking orphans
        var resolvedItems: [ExtractedItem] = []
        var orphanedCount = 0
        
        for itemId in itemIds {
            if let item = itemsById[itemId] {
                resolvedItems.append(item)
            } else {
                orphanedCount += 1
            }
        }
        
        // Log orphaned IDs if any (light logging)
        if orphanedCount > 0 {
            AppLogger.log(
                AppLogger.STORE,
                "ItemResolver found \(orphanedCount) orphaned item IDs (skipped)"
            )
        }
        
        return resolvedItems
    }
    
    /// Resolves a single item ID to its full ExtractedItem instance
    /// Returns nil if item is not found (orphaned)
    /// - Parameter itemId: Item ID to resolve
    /// - Returns: Resolved item, or nil if not found
    static func resolveItem(itemId: String) -> ExtractedItem? {
        let resolved = resolveItems(itemIds: [itemId])
        return resolved.first
    }
}
