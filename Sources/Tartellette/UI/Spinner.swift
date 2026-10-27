import AppKit

/// Frames of a classic 12-spoke activity indicator, as template images sized for menu items.
/// NSMenuItem images don't animate, so the menu builder cycles through these with a timer.
enum Spinner {
  static let spokes = 12

  static let frames: [NSImage] = (0..<spokes).map { frame(rotation: $0) }

  private static func frame(rotation: Int) -> NSImage {
    let side: CGFloat = 14
    let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      let center = NSPoint(x: rect.midX, y: rect.midY)
      for i in 0..<spokes {
        // Spoke `rotation` is the brightest; the trail fades clockwise behind it.
        let age = (rotation - i + spokes) % spokes
        NSColor.black.withAlphaComponent(1 - CGFloat(age) / CGFloat(spokes) * 0.85).setStroke()
        let angle = CGFloat.pi / 2 - CGFloat(i) * 2 * .pi / CGFloat(spokes)
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: center.x + cos(angle) * 3.2, y: center.y + sin(angle) * 3.2))
        path.line(to: NSPoint(x: center.x + cos(angle) * 6.2, y: center.y + sin(angle) * 6.2))
        path.stroke()
      }
      return true
    }
    img.isTemplate = true
    return img
  }
}
