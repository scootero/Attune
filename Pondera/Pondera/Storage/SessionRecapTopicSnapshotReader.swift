//
//  SessionRecapTopicSnapshotReader.swift
//  Pondera
//
//  Side-effect-free topic decoding for the read-only Session Recap feature.
//

import Foundation

enum SessionRecapTopicSnapshotReader {
    static func load(from fileURL: URL = AppPaths.topicsFileURL) -> [TopicAggregate] {
        guard let data = try? Data(contentsOf: fileURL),
              let topics = try? JSONDecoder().decode([TopicAggregate].self, from: data) else {
            return []
        }
        return topics
    }
}
