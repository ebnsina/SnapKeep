import AppKit

/// Background presets for the Beautify view.
enum BeautifyBackground: String, CaseIterable, Identifiable {
    case ocean, sunset, mint, grape, graphite, none
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ocean: return "Ocean"
        case .sunset: return "Sunset"
        case .mint: return "Mint"
        case .grape: return "Grape"
        case .graphite: return "Graphite"
        case .none: return "None"
        }
    }

    /// Gradient stops (top-leading → bottom-trailing). Empty = transparent.
    var colors: [NSColor] {
        switch self {
        case .ocean:    return [NSColor(red: 0.24, green: 0.51, blue: 0.96, alpha: 1),
                                NSColor(red: 0.40, green: 0.29, blue: 0.90, alpha: 1)]
        case .sunset:   return [NSColor(red: 0.98, green: 0.55, blue: 0.34, alpha: 1),
                                NSColor(red: 0.93, green: 0.28, blue: 0.51, alpha: 1)]
        case .mint:     return [NSColor(red: 0.36, green: 0.90, blue: 0.68, alpha: 1),
                                NSColor(red: 0.22, green: 0.62, blue: 0.86, alpha: 1)]
        case .grape:    return [NSColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1),
                                NSColor(red: 0.30, green: 0.20, blue: 0.65, alpha: 1)]
        case .graphite: return [NSColor(red: 0.24, green: 0.24, blue: 0.27, alpha: 1),
                                NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)]
        case .none:     return []
        }
    }
}

/// Composites a capture onto a styled background at full resolution.
enum BeautifyRenderer {
    static func render(image: NSImage, background: BeautifyBackground,
                       padding: CGFloat, cornerRadius: CGFloat, shadow: Bool) -> NSImage {
        let scale: CGFloat = 2 // export at 2x for crisp output
        let imgSize = image.size
        let outSize = CGSize(width: imgSize.width + padding * 2,
                             height: imgSize.height + padding * 2)
        let pxW = Int(outSize.width * scale), pxH = Int(outSize.height * scale)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        rep.size = outSize

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        let ctx = gctx.cgContext
        ctx.scaleBy(x: scale, y: scale)

        // Background gradient (or transparent).
        let colors = background.colors
        if colors.count == 2,
           let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: [colors[0].cgColor, colors[1].cgColor] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: outSize.height),
                                   end: CGPoint(x: outSize.width, y: 0), options: [])
        }

        let imageRect = CGRect(x: padding, y: padding, width: imgSize.width, height: imgSize.height)
        let clip = NSBezierPath(roundedRect: imageRect, xRadius: cornerRadius, yRadius: cornerRadius)

        if shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                          color: NSColor.black.withAlphaComponent(0.35).cgColor)
            NSColor.black.setFill()
            clip.fill()
            ctx.restoreGState()
        }

        ctx.saveGState()
        clip.addClip()
        image.draw(in: imageRect)
        ctx.restoreGState()

        NSGraphicsContext.restoreGraphicsState()

        let out = NSImage(size: outSize)
        out.addRepresentation(rep)
        return out
    }
}
