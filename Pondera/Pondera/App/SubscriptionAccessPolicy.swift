//
//  SubscriptionAccessPolicy.swift
//  Pondera
//
//  Pure Free/Pro feature decisions shared by UI and persistence guards.
//

import Foundation

struct SubscriptionAccessPolicy: Equatable {
    let hasProAccess: Bool

    func canStartCheckIn(todayCheckInCount: Int) -> Bool {
        hasProAccess || todayCheckInCount < SubscriptionConfig.freeCheckInsPerDay
    }

    var canUseListeningSessions: Bool { hasProAccess }
    var canUseVoiceIntentions: Bool { hasProAccess }
    var canUseInsights: Bool { hasProAccess }
    var canUseMomentumHistory: Bool { hasProAccess }
    var canExportData: Bool { hasProAccess }

    func canAddIntention(currentCount: Int) -> Bool {
        currentCount < activeIntentionLimit
    }

    /// Final persistence guard for a proposed active set.
    ///
    /// Free users may always save a set at or below the Free limit. A downgraded
    /// user who already has multiple active intentions may edit or remove those
    /// existing IDs, but cannot introduce a new ID while remaining over the limit.
    func canSaveIntentions(baselineIDs: Set<String>, proposedIDs: [String]) -> Bool {
        let uniqueProposedIDs = Set(proposedIDs)
        guard uniqueProposedIDs.count == proposedIDs.count else { return false }
        guard proposedIDs.count <= SubscriptionConfig.maximumActiveIntentions else { return false }
        guard !hasProAccess else { return true }

        if proposedIDs.count <= SubscriptionConfig.freeActiveIntentionsLimit {
            return true
        }

        return uniqueProposedIDs.isSubset(of: baselineIDs)
            && proposedIDs.count <= baselineIDs.count
    }

    private var activeIntentionLimit: Int {
        hasProAccess
            ? SubscriptionConfig.maximumActiveIntentions
            : SubscriptionConfig.freeActiveIntentionsLimit
    }
}

