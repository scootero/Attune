//
//  InsightSeenStore.swift
//  Attune
//
//  Lightweight local presentation state for captures the user has already
//  encountered on the Insights home. This does not change review state.
//

import Foundation

struct InsightSeenStore {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "attune.insights.seenCaptureIDs.v1"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func unseenIDs(in itemIDs: [String]) -> Set<String> {
        Set(itemIDs).subtracting(seenIDs)
    }

    func markSeen(_ itemIDs: Set<String>, retaining knownItemIDs: [String]) {
        guard !itemIDs.isEmpty else { return }
        let knownIDs = Set(knownItemIDs)
        let updated = seenIDs
            .union(itemIDs)
            .intersection(knownIDs)
        defaults.set(Array(updated).sorted(), forKey: key)
    }

    private var seenIDs: Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
