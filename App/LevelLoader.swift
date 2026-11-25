import Foundation
import GrappleCore

/// Loads level JSON from the app bundle (issue #16).
enum LevelLoader {
    /// Loads `<name>.json` using the shared `chunks.json` library.
    /// A broken level file is a developer error, so this stops with a message naming the problem;
    /// the core tests load every shipped level, which catches mistakes before they reach the device.
    static func load(_ name: String) -> Level {
        guard let levelURL = Bundle.main.url(forResource: name, withExtension: "json"),
              let chunksURL = Bundle.main.url(forResource: "chunks", withExtension: "json")
        else { fatalError("Level files missing from the app bundle: \(name).json / chunks.json") }
        do {
            return try LevelBuilder.load(levelData: Data(contentsOf: levelURL), chunkData: Data(contentsOf: chunksURL))
        } catch {
            fatalError("Level \"\(name)\" failed to load: \(error)")
        }
    }
}
