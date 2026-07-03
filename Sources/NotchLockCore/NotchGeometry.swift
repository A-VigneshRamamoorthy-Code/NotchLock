import CoreGraphics
import Foundation

/// Geometry describing where the notch is and where the pull-string hangs from.
///
/// All rectangles/points are in AppKit global screen coordinates
/// (origin bottom-left, +y up).
public struct NotchGeometry: Equatable, Sendable {
    /// The notch rectangle at the very top-centre of the screen.
    public let notchRect: CGRect
    /// The anchor point the string hangs from — the bottom-centre of the notch.
    public let shoulder: CGPoint
    /// Whether a real hardware notch was detected (vs. a synthesized fallback).
    public let hasNotch: Bool

    public init(notchRect: CGRect, shoulder: CGPoint, hasNotch: Bool) {
        self.notchRect = notchRect
        self.shoulder = shoulder
        self.hasNotch = hasNotch
    }

    /// Compute notch geometry from a screen description.
    ///
    /// - Parameters:
    ///   - screenFrame: the screen's frame in global coordinates.
    ///   - safeAreaTop: the screen's top safe-area inset (>0 implies a notch).
    ///   - auxLeft: `auxiliaryTopLeftArea` — menu-bar area left of the notch.
    ///   - auxRight: `auxiliaryTopRightArea` — menu-bar area right of the notch.
    public static func compute(screenFrame: CGRect,
                               safeAreaTop: CGFloat,
                               auxLeft: CGRect?,
                               auxRight: CGRect?,
                               fallbackNotchWidth: CGFloat = 200,
                               fallbackNotchHeight: CGFloat = 32) -> NotchGeometry {
        let topY = screenFrame.maxY

        if let l = auxLeft, let r = auxRight, r.minX > l.maxX {
            // The notch is the gap between the two auxiliary menu-bar areas.
            let notchWidth = r.minX - l.maxX
            let notchHeight = max(l.height, r.height, safeAreaTop)
            let notchRect = CGRect(x: l.maxX,
                                   y: topY - notchHeight,
                                   width: notchWidth,
                                   height: notchHeight)
            let shoulder = CGPoint(x: notchRect.midX, y: notchRect.minY)
            return NotchGeometry(notchRect: notchRect, shoulder: shoulder, hasNotch: true)
        }

        // Fallback: synthesize a notch-shaped region centred on the menu bar so
        // the app also works on Macs without a hardware notch.
        let h = safeAreaTop > 0 ? safeAreaTop : fallbackNotchHeight
        let w = fallbackNotchWidth
        let notchRect = CGRect(x: screenFrame.midX - w / 2,
                               y: topY - h,
                               width: w,
                               height: h)
        let shoulder = CGPoint(x: notchRect.midX, y: notchRect.minY)
        return NotchGeometry(notchRect: notchRect, shoulder: shoulder, hasNotch: safeAreaTop > 0)
    }

    /// Euclidean distance from `point` to the shoulder anchor.
    public func distanceToShoulder(_ point: CGPoint) -> CGFloat {
        hypot(point.x - shoulder.x, point.y - shoulder.y)
    }
}
