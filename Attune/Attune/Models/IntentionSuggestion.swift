import Foundation

enum IntentionSuggestionFeature {
    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

struct IntentionSuggestionEvidence: Codable, Equatable, Identifiable {
    let itemId: String
    let sessionId: String
    let sessionDate: Date
    let quote: String
    var id: String { itemId }
}

struct IntentionSuggestionTopic: Equatable {
    let topicKey: String
    let title: String
    let categories: [String]
    let evidence: [IntentionSuggestionEvidence]
    let distinctSessionCount: Int
    let currentMonthSessionCount: Int
    let firstSessionAt: Date
    let lastSessionAt: Date
}

struct SuggestedIntentionAction: Codable, Equatable, Identifiable {
    let actionId: String
    let topicKey: String
    let topicTitle: String
    let title: String
    let targetValue: Double
    let unit: String
    let timeframe: String
    let reason: String
    let evidence: [IntentionSuggestionEvidence]
    let sourceTitle: String?
    let sourceURL: String?
    let safetyNote: String?
    let generatedAt: Date
    var distinctSessionCount: Int? = nil
    var currentMonthSessionCount: Int? = nil
    var id: String { actionId }
}

enum IntentionSuggestionOutcome: String, Codable {
    case accepted
    case declined
}

struct IntentionSuggestionHistoryEntry: Codable, Equatable {
    let actionId: String
    let topicKey: String
    let outcome: IntentionSuggestionOutcome
    let decidedAt: Date
}

struct IntentionSuggestionSnapshot: Codable, Equatable {
    var firstLaunchAt: Date?
    var isExistingInstall: Bool
    var completedOpportunityKeys: Set<String>
    var lastNudgeAt: Date?
    var lastGenerationAttemptAt: Date?
    var outstanding: SuggestedIntentionAction?
    var history: [IntentionSuggestionHistoryEntry]

    static let empty = IntentionSuggestionSnapshot(
        firstLaunchAt: nil,
        isExistingInstall: false,
        completedOpportunityKeys: [],
        lastNudgeAt: nil,
        lastGenerationAttemptAt: nil,
        outstanding: nil,
        history: []
    )

    private enum CodingKeys: String, CodingKey {
        case firstLaunchAt, isExistingInstall, completedOpportunityKeys
        case lastNudgeAt, lastGenerationAttemptAt, outstanding, history
    }

    init(
        firstLaunchAt: Date?,
        isExistingInstall: Bool,
        completedOpportunityKeys: Set<String>,
        lastNudgeAt: Date?,
        lastGenerationAttemptAt: Date?,
        outstanding: SuggestedIntentionAction?,
        history: [IntentionSuggestionHistoryEntry]
    ) {
        self.firstLaunchAt = firstLaunchAt
        self.isExistingInstall = isExistingInstall
        self.completedOpportunityKeys = completedOpportunityKeys
        self.lastNudgeAt = lastNudgeAt
        self.lastGenerationAttemptAt = lastGenerationAttemptAt
        self.outstanding = outstanding
        self.history = history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstLaunchAt = try container.decodeIfPresent(Date.self, forKey: .firstLaunchAt)
        isExistingInstall = try container.decodeIfPresent(Bool.self, forKey: .isExistingInstall) ?? false
        completedOpportunityKeys = try container.decodeIfPresent(Set<String>.self, forKey: .completedOpportunityKeys) ?? []
        lastNudgeAt = try container.decodeIfPresent(Date.self, forKey: .lastNudgeAt)
        lastGenerationAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastGenerationAttemptAt)
        outstanding = try container.decodeIfPresent(SuggestedIntentionAction.self, forKey: .outstanding)
        history = try container.decodeIfPresent([IntentionSuggestionHistoryEntry].self, forKey: .history) ?? []
    }
}
