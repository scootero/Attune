//
//  AIUsageLimit.swift
//  Attune
//
//  Anonymous installation identity and user-facing monthly AI allowance state.
//

import Combine
import Foundation

struct AIUsageStatus: Codable, Equatable {
    let usedUnits: Int
    let limitUnits: Int
    let warningAtUnits: Int
    let warning: Bool
    let limited: Bool
    let resetsAt: String
    let period: String

    var resetDate: Date? {
        ISO8601DateFormatter().date(from: resetsAt)
    }
}

struct AIUsageErrorPayload: Decodable {
    let code: String?
    let resetsAt: String?
}

enum AIInstallationIdentity {
    private static let defaultsKey = "attune.ai.installationId"

    static var value: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey),
           existing.count >= 16 {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: defaultsKey)
        return created
    }
}

struct AIUsageNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case warning
        case limited
    }

    let id = UUID()
    let kind: Kind
    let resetDate: Date?

    var title: String {
        switch kind {
        case .warning: return "AI allowance running low"
        case .limited: return "Monthly AI limit reached"
        }
    }

    var message: String {
        let refresh = resetDate.map {
            " Your allowance refreshes \($0.formatted(date: .abbreviated, time: .omitted))."
        } ?? " Your allowance refreshes next month."
        switch kind {
        case .warning:
            return "You’re nearing this month’s included AI processing limit." + refresh
        case .limited:
            return "You’ve used this month’s included AI processing. Everything already saved in Attune is still available." + refresh
        }
    }
}

@MainActor
final class AIUsageNoticeCenter: ObservableObject {
    static let shared = AIUsageNoticeCenter()

    @Published var notice: AIUsageNotice?
    private let warningPeriodKey = "attune.ai.lastUsageWarningPeriod"

    private init() {}

    func consume(_ status: AIUsageStatus) {
        if status.limited {
            notice = AIUsageNotice(kind: .limited, resetDate: status.resetDate)
            return
        }
        guard status.warning, !status.period.isEmpty else { return }
        guard UserDefaults.standard.string(forKey: warningPeriodKey) != status.period else { return }
        UserDefaults.standard.set(status.period, forKey: warningPeriodKey)
        notice = AIUsageNotice(kind: .warning, resetDate: status.resetDate)
    }

    func showLimit(resetDate: Date?) {
        notice = AIUsageNotice(kind: .limited, resetDate: resetDate)
    }
}
