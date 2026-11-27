import Foundation
import GrappleCore

/// Saves the player's settings (#36) on the device.
enum SettingsStore {
    private static let key = "playerSettings.v1"

    static func load() -> PlayerSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(PlayerSettings.self, from: data)
        else { return PlayerSettings() }
        return settings
    }

    static func save(_ settings: PlayerSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
