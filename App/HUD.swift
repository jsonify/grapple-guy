import SpriteKit

/// A rounded HUD panel with centered text that shrinks to fit a maximum width.
final class Card: SKNode {
    private let background = SKShapeNode()
    private let label = SKLabelNode()
    private let padding: CGSize
    private let cornerRadius: CGFloat
    private var lastText: NSAttributedString?
    private var naturalSize: CGSize = .zero
    private var fitScale: CGFloat = 1
    /// On-screen size after fitting.
    var size: CGSize { CGSize(width: naturalSize.width * fitScale, height: naturalSize.height * fitScale) }

    init(fill: SKColor = Palette.hudPanel, stroke: SKColor = Palette.hudBorder,
         padding: CGSize = CGSize(width: 18, height: 10), cornerRadius: CGFloat = 18) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        super.init()
        background.fillColor = fill
        background.strokeColor = stroke
        background.lineWidth = 3
        addChild(background)
        label.numberOfLines = 0
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `text` (nil hides the card), scaled down if wider than `maxWidth` screen points.
    func set(_ text: NSAttributedString?, maxWidth: CGFloat) {
        guard let text else {
            isHidden = true
            lastText = nil
            return
        }
        isHidden = false
        if text != lastText {
            lastText = text
            label.attributedText = text
            let rect = label.frame.insetBy(dx: -padding.width, dy: -padding.height)
            background.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            naturalSize = rect.size
        }
        fitScale = naturalSize.width > maxWidth && naturalSize.width > 0 ? maxWidth / naturalSize.width : 1
        if action(forKey: "bump") == nil { setScale(fitScale) }
    }

    /// A quick pop, e.g. when the swing count changes.
    func bump() {
        removeAction(forKey: "bump")
        setScale(fitScale * 1.3)
        run(.scale(to: fitScale, duration: 0.2), withKey: "bump")
    }
}
