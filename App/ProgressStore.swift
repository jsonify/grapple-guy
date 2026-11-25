import Foundation
import GrappleCore

/// Saves each level's best results on the device (issue #18).
enum ProgressStore {
    private static let key = "levelRecords.v1"

    static func record(for level: String) -> LevelRecord? {
        load()[level]
    }

    /// Merges a finished run into the saved record and returns the updated record.
    @discardableResult
    static func save(_ run: RunResult, for level: String) -> LevelRecord {
        var records = load()
        let merged = (records[level] ?? LevelRecord()).merging(run)
        records[level] = merged
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return merged
    }

    private static func load() -> [String: LevelRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([String: LevelRecord].self, from: data)
        else { return [:] }
        return records
    }
}
