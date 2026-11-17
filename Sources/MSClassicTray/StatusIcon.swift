import AppKit
import MSClassicCore

/// A simple, tilted two-tone maple leaf (slender Japanese-maple lobes), tinted by server status.
enum StatusIcon {
    static func color(for state: ServerState) -> NSColor {
        switch state {
        case .up: .systemGreen
        case .maintenance: .systemRed
        case .overrunning: .systemOrange
        case .unknown: .systemGray
        }
    }

    /// Non-template image, so the menu bar shows the real status color.
    static func image(for state: ServerState, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, color: color(for: state))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "MapleStory Classic World: \(state.rawValue)"
        return image
    }

    /// Draws the leaf fitted into `rect`: the base color, with the half right of the midrib shaded darker.
    static func draw(in rect: NSRect, color: NSColor) {
        let (leaf, shade) = leafPaths(fittedTo: rect)
        color.setFill()
        leaf.fill()
        NSGraphicsContext.saveGraphicsState()
        leaf.addClip()
        (color.blended(withFraction: 0.3, of: .black) ?? color).setFill()
        shade.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Geometry (100×100 design space, y up)

    private struct Lobe {
        let angle: CGFloat   // degrees, clockwise from straight up
        let length: CGFloat
        let width: CGFloat
    }

    private static let center = CGPoint(x: 50, y: 42)
    private static let notchRadius: CGFloat = 13
    private static let tilt: CGFloat = 35
    private static let lobes = [
        Lobe(angle: 0, length: 56, width: 12),
        Lobe(angle: 54, length: 50, width: 11),
        Lobe(angle: 110, length: 36, width: 9),
        Lobe(angle: 250, length: 36, width: 9),
        Lobe(angle: 306, length: 50, width: 11),
    ]
    /// Where each lobe's trailing edge ends (the notch before the next lobe).
    private static let notchAngles: [CGFloat] = [27, 82, .nan /* stem */, 278, 333]

    static func leafPaths(fittedTo rect: NSRect) -> (leaf: NSBezierPath, shade: NSBezierPath) {
        let leaf = NSBezierPath()
        leaf.move(to: point(at: -27, radius: notchRadius))
        for (i, lobe) in lobes.enumerated() {
            let u = direction(lobe.angle)
            let v = CGPoint(x: u.y, y: -u.x) // perpendicular, toward increasing angle
            let tip = offset(center, u, lobe.length, v, 0)
            leaf.curve(to: tip,
                       controlPoint1: offset(center, u, lobe.length * 0.42, v, -lobe.width),
                       controlPoint2: offset(center, u, lobe.length * 0.85, v, -lobe.width * 0.25))
            let isStem = notchAngles[i].isNaN
            let end = isStem ? CGPoint(x: 52, y: 33) : point(at: notchAngles[i], radius: notchRadius)
            leaf.curve(to: end,
                       controlPoint1: offset(center, u, lobe.length * 0.85, v, lobe.width * 0.25),
                       controlPoint2: offset(center, u, lobe.length * 0.42, v, lobe.width))
            if isStem {
                leaf.curve(to: CGPoint(x: 55, y: 3), controlPoint1: CGPoint(x: 54, y: 22), controlPoint2: CGPoint(x: 57, y: 12))
                leaf.curve(to: CGPoint(x: 51, y: 3), controlPoint1: CGPoint(x: 54.5, y: 1.5), controlPoint2: CGPoint(x: 52, y: 1.5))
                leaf.curve(to: CGPoint(x: 48, y: 33), controlPoint1: CGPoint(x: 53, y: 12), controlPoint2: CGPoint(x: 50, y: 22))
            }
        }
        leaf.close()

        // Everything right of the midrib line (stem → top tip).
        let shade = NSBezierPath()
        shade.move(to: CGPoint(x: 53, y: -10))
        shade.line(to: CGPoint(x: 50, y: 110))
        shade.line(to: CGPoint(x: 140, y: 110))
        shade.line(to: CGPoint(x: 140, y: -10))
        shade.close()

        var rotate = AffineTransform()
        rotate.rotate(byDegrees: tilt)
        leaf.transform(using: rotate)
        shade.transform(using: rotate)

        let bounds = leaf.bounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var fit = AffineTransform(translationByX: rect.midX - bounds.midX * scale, byY: rect.midY - bounds.midY * scale)
        fit.scale(scale)
        leaf.transform(using: fit)
        shade.transform(using: fit)
        return (leaf, shade)
    }

    private static func direction(_ degrees: CGFloat) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: sin(r), y: cos(r))
    }

    private static func point(at degrees: CGFloat, radius: CGFloat) -> CGPoint {
        offset(center, direction(degrees), radius, .zero, 0)
    }

    private static func offset(_ p: CGPoint, _ u: CGPoint, _ s: CGFloat, _ v: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: p.x + u.x * s + v.x * t, y: p.y + u.y * s + v.y * t)
    }
}
