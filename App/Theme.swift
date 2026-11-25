import SpriteKit
import UIKit
import GrappleCore

/// Cartoon rooftops at sunset: colours, fonts and text styling (art direction chosen by the developer).
enum Palette {
    // Sky and city
    static let skyTop = SKColor(red: 0.22, green: 0.20, blue: 0.48, alpha: 1)
    static let skyMid = SKColor(red: 0.93, green: 0.45, blue: 0.45, alpha: 1)
    static let skyBottom = SKColor(red: 1.00, green: 0.78, blue: 0.50, alpha: 1)
    static let sun = SKColor(red: 1.00, green: 0.90, blue: 0.58, alpha: 1)
    static let farCity = SKColor(red: 0.62, green: 0.36, blue: 0.55, alpha: 1)
    static let farWindows = SKColor(red: 1.00, green: 0.84, blue: 0.55, alpha: 0.55)
    static let nearCity = SKColor(red: 0.34, green: 0.21, blue: 0.40, alpha: 1)
    static let nearWindows = SKColor(red: 1.00, green: 0.80, blue: 0.42, alpha: 0.85)
    static let cloud = SKColor(red: 1.00, green: 0.86, blue: 0.82, alpha: 0.75)
    static let background = skyBottom

    // Course
    static let outline = SKColor(red: 0.12, green: 0.09, blue: 0.18, alpha: 1)
    static let rooftop = SKColor(red: 0.36, green: 0.38, blue: 0.53, alpha: 1)
    static let rooftopRim = SKColor(red: 0.64, green: 0.67, blue: 0.82, alpha: 1)
    static let rooftopWindow = SKColor(red: 0.27, green: 0.28, blue: 0.41, alpha: 1)
    static let grip = SKColor(red: 1.00, green: 0.55, blue: 0.13, alpha: 1)
    static let gripLight = SKColor(red: 1.00, green: 0.80, blue: 0.38, alpha: 1)
    static let gripGlow = SKColor(red: 1.00, green: 0.62, blue: 0.22, alpha: 0.35)

    static let water = SKColor(red: 0.22, green: 0.58, blue: 0.98, alpha: 0.92)
    static let waterLight = SKColor(red: 0.62, green: 0.86, blue: 1.00, alpha: 1)
    static let sand = SKColor(red: 0.98, green: 0.84, blue: 0.54, alpha: 1)
    static let sandDark = SKColor(red: 0.85, green: 0.66, blue: 0.36, alpha: 1)

    // Characters and pickups
    static let stickman = SKColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)
    static let crashed = SKColor(red: 1.00, green: 0.38, blue: 0.33, alpha: 1)
    static let rope = SKColor(red: 0.97, green: 0.97, blue: 1.00, alpha: 1)
    static let gem = SKColor(red: 0.28, green: 0.95, blue: 0.86, alpha: 1)
    static let flag = SKColor(red: 0.95, green: 0.22, blue: 0.27, alpha: 1)
    static let checkpoint = SKColor(red: 1.00, green: 0.85, blue: 0.25, alpha: 1)
    static let finish = SKColor(red: 0.32, green: 0.86, blue: 0.42, alpha: 1)
    static let boost = SKColor(red: 0.42, green: 0.86, blue: 1.00, alpha: 1)
    static let miss = SKColor(red: 1.00, green: 0.42, blue: 0.36, alpha: 1)

    // Bots (#32)
    static let botRita = SKColor(red: 1.00, green: 0.50, blue: 0.75, alpha: 1)
    static let botSam = SKColor(red: 0.45, green: 0.88, blue: 0.48, alpha: 1)
    static let botPip = SKColor(red: 0.40, green: 0.82, blue: 1.00, alpha: 1)

    // HUD
    static let hudPanel = SKColor(red: 0.12, green: 0.09, blue: 0.20, alpha: 0.82)
    static let hudBorder = SKColor(white: 1, alpha: 0.9)
    static let hudText = SKColor.white
    static let gold = SKColor(red: 1.00, green: 0.84, blue: 0.22, alpha: 1)
    static let overPar = SKColor(red: 1.00, green: 0.48, blue: 0.42, alpha: 1)
}

enum Theme {
    static let heavyFont = "AvenirNext-Heavy"
    static let boldFont = "AvenirNext-Bold"

    /// Centered, optionally outlined text for SKLabelNode.attributedText.
    static func text(_ string: String, size: CGFloat, color: SKColor = Palette.hudText,
                     outline: SKColor? = nil, font: String = heavyFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: font, size: size) ?? .systemFont(ofSize: size, weight: .heavy),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if let outline {
            attributes[.strokeColor] = outline
            attributes[.strokeWidth] = -5.0  // negative: fill and stroke
        }
        return NSAttributedString(string: string, attributes: attributes)
    }
}

extension Theme {
    /// Concatenates styled pieces (a join, not `+`, keeps the type checker fast).
    static func join(_ parts: [NSAttributedString]) -> NSAttributedString {
        let joined = NSMutableAttributedString()
        for part in parts { joined.append(part) }
        return joined
    }
}

extension CGPoint {
    init(_ v: Vec2) { self.init(x: v.x, y: v.y) }
}

extension Vec2 {
    init(_ p: CGPoint) { self.init(Double(p.x), Double(p.y)) }
}

/// Small deterministic generator for scenery layout (so the skyline doesn't change between runs).
struct SceneryRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func next(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
}
