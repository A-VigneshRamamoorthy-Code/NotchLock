import AppKit
import NotchLockCore

/// A branded, full‑opacity header for the right‑click menu. Using a custom view
/// (instead of a disabled `NSMenuItem`) means macOS never greys it out: it shows
/// the cord icon, the "NotchLock" title, and a short subtitle at full contrast.
final class MenuHeaderView: NSView {
    init(style: ChainStyle, subtitle: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 56))
        autoresizingMask = [.width]

        let iconSize = NSSize(width: 26, height: 34)
        let iconView = NSImageView(frame: NSRect(x: 16, y: (56 - iconSize.height) / 2,
                                                 width: iconSize.width, height: iconSize.height))
        iconView.imageScaling = .scaleProportionallyUpOrDown
        if let cg = ChainRenderer.icon(for: style, size: CGSize(width: iconSize.width, height: iconSize.height)) {
            iconView.image = NSImage(cgImage: cg, size: iconSize)
        }
        iconView.autoresizingMask = [.maxXMargin]
        addSubview(iconView)

        let textX: CGFloat = 16 + iconSize.width + 12
        let title = NSTextField(labelWithString: "NotchLock")
        title.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        title.textColor = .labelColor
        title.frame = NSRect(x: textX, y: 28, width: 200, height: 20)
        title.autoresizingMask = [.width]
        addSubview(title)

        let sub = NSTextField(labelWithString: subtitle)
        sub.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        sub.textColor = .secondaryLabelColor
        sub.frame = NSRect(x: textX, y: 9, width: 220, height: 16)
        sub.autoresizingMask = [.width]
        addSubview(sub)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
