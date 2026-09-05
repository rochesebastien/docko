import AppKit
import SwiftUI

extension NSColor {
    /// Couleur depuis « #RRGGBB » (le dièse est optionnel).
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        guard let color = usingColorSpace(.sRGB) else { return "#4A90E2" }
        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Pastille colorée pour les items de menu.
    static func dotImage(hex: String, size: CGFloat = 12) -> NSImage {
        let color = NSColor(hex: hex) ?? .systemBlue
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex) ?? .systemBlue)
    }
}
