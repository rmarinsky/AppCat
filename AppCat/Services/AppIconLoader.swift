import AppKit

/// Loads app icons for picker/switcher tiles. `NSWorkspace.icon(forFile:)` returns an image
/// carrying every representation of the .icns (up to 1024×1024) — setting `.size` only changes
/// the logical size, the large reps stay resident. Retaining that for a few hundred installed
/// apps costs tens of MB, so re-render into a single bitmap rep at tile size (2x for Retina)
/// and drop the rest.
enum AppIconLoader {
    static func icon(forFile path: String, side: CGFloat = 64) -> NSImage {
        downsampled(NSWorkspace.shared.icon(forFile: path), side: side)
    }

    static func downsampled(_ source: NSImage, side: CGFloat = 64) -> NSImage {
        let pixelSide = Int(side * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSide,
            pixelsHigh: pixelSide,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            source.size = NSSize(width: side, height: side)
            return source
        }
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = context
            context.imageInterpolation = .high
            source.draw(
                in: NSRect(x: 0, y: 0, width: side, height: side),
                from: .zero,
                operation: .copy,
                fraction: 1
            )
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }
}
