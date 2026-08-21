import Combine
import SwiftUI

extension Notification.Name {
    static let attuneReviewIntentionSuggestion = Notification.Name("attune.intentionSuggestion.review")
    static let attuneIntentionSuggestionDidResolve = Notification.Name("attune.intentionSuggestion.didResolve")
}

/// Process-local presentation state for the brief suggestion surfaces. The
/// durable source of truth remains IntentionSuggestionStore.
@MainActor
final class IntentionSuggestionToastCenter: ObservableObject {
    static let shared = IntentionSuggestionToastCenter()

    @Published private(set) var talkSuggestion: SuggestedIntentionAction?
    @Published private(set) var homeSuggestion: SuggestedIntentionAction?

    private var pendingHomeSuggestion: SuggestedIntentionAction?

    private init() {}

    func presentAfterProcessing(_ suggestion: SuggestedIntentionAction) {
        talkSuggestion = suggestion
        pendingHomeSuggestion = suggestion
    }

    func presentPendingHomeSuggestion() {
        guard let pendingHomeSuggestion else { return }
        homeSuggestion = pendingHomeSuggestion
        self.pendingHomeSuggestion = nil
    }

    func dismissTalkSuggestion(id: String) {
        guard talkSuggestion?.id == id else { return }
        talkSuggestion = nil
    }

    func dismissHomeSuggestion(id: String) {
        guard homeSuggestion?.id == id else { return }
        homeSuggestion = nil
    }

    func resolveSuggestion(id: String) {
        if talkSuggestion?.id == id { talkSuggestion = nil }
        if homeSuggestion?.id == id { homeSuggestion = nil }
        if pendingHomeSuggestion?.id == id { pendingHomeSuggestion = nil }
    }
}

struct IntentionSuggestionToast: View {
    let suggestion: SuggestedIntentionAction
    let onReview: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(AttuneTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggested intention")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AttuneTheme.textSecondary)
                    Text(suggestion.title)
                        .font(.headline)
                        .foregroundStyle(AttuneTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(suggestion.targetValue.formatted()) \(suggestion.unit) · \(suggestion.timeframe)")
                        .font(.subheadline)
                        .foregroundStyle(AttuneTheme.textSecondary)
                }

                Spacer(minLength: 4)
            }

            HStack(spacing: 10) {
                Button("Not for me", action: onDismiss)
                    .buttonStyle(.borderless)
                Spacer(minLength: 4)
                Button("Review", action: onReview)
                    .buttonStyle(.borderedProminent)
                    .tint(AttuneTheme.accent)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(
            AttuneTheme.backgroundRaised.opacity(0.48),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 9)
        .accessibilityElement(children: .contain)
    }
}
