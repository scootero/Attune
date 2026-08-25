import Foundation

@MainActor
final class OneThingModeStore {
    static let shared = OneThingModeStore()
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? AppPaths.oneThingModeFileURL
    }

    func load() -> OneThingModeState {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(OneThingModeState.self, from: data)) ?? .empty
    }

    func activate(focusedIntentionId: String, now: Date = Date()) throws {
        var state = load()
        state.focusedIntentionId = focusedIntentionId
        state.activatedAt = now
        try save(state)
    }

    func select(_ intentionId: String) throws {
        var state = load()
        guard state.isActive else { return }
        state.focusedIntentionId = intentionId
        try save(state)
    }

    func exit(now: Date = Date()) throws {
        var state = load()
        state.focusedIntentionId = nil
        state.activatedAt = nil
        state.lastExitedAt = now
        try save(state)
    }

    private func save(_ state: OneThingModeState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
