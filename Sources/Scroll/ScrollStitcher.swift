import CoreGraphics

/// Stitches a sequence of same-width frames captured while the user scrolls into one tall
/// image. For each new frame it finds the vertical scroll delta by matching a downsampled
/// grayscale version against the previous frame, then keeps only the newly revealed rows.
final class ScrollStitcher {
    private var frames: [CGImage] = []
    private var deltas: [Int] = []          // full-res pixel offset of each frame from the top
    private var prevGray: [UInt8]?
    private var grayW = 0, grayH = 0

    private let matchWidth = 180            // downsample width for matching
    private let minOverlapFraction = 0.35   // require this much overlap to trust a match

    var frameCount: Int { frames.count }

    /// Feed a freshly captured region frame. Returns the total stitched height so far (px).
    @discardableResult
    func add(_ frame: CGImage) -> Int {
        let (gray, gw, gh) = Self.grayscale(frame, targetWidth: matchWidth)

        defer { prevGray = gray; grayW = gw; grayH = gh }

        // First frame seeds the stitch.
        guard let prev = prevGray, !frames.isEmpty, gw == grayW, gh == grayH else {
            frames = [frame]; deltas = [0]
            return frame.height
        }

        guard let shiftLow = bestShift(prev: prev, new: gray, w: gw, h: gh) else {
            return totalHeight() // no confident match: skip this frame
        }
        // Convert the low-res shift back to full-res rows.
        let fullDelta = Int((Double(shiftLow) * Double(frame.height) / Double(gh)).rounded())
        guard fullDelta >= 4 else { return totalHeight() } // negligible / no scroll

        frames.append(frame)
        deltas.append(min(fullDelta, frame.height))
        return totalHeight()
    }

    private func totalHeight() -> Int {
        guard let first = frames.first else { return 0 }
        return first.height + deltas.dropFirst().reduce(0, +)
    }

    /// Compose the accumulated frames into one tall image.
    func compose() -> CGImage? {
        guard let first = frames.first else { return nil }
        let W = first.width
        let T = totalHeight()
        guard let ctx = CGContext(data: nil, width: W, height: T, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        var topOffset = 0
        for (i, frame) in frames.enumerated() {
            topOffset += deltas[i] // deltas[0] == 0
            // Place frame's top row at `topOffset` from the top; context is y-up.
            let y = CGFloat(T - topOffset - frame.height)
            ctx.draw(frame, in: CGRect(x: 0, y: y, width: CGFloat(W), height: CGFloat(frame.height)))
        }
        return ctx.makeImage()
    }

    // MARK: Matching

    /// Best downward scroll shift `s` (low-res rows): new[0..<h-s] ≈ prev[s..<h].
    private func bestShift(prev: [UInt8], new: [UInt8], w: Int, h: Int) -> Int? {
        let minOverlap = max(4, Int(Double(h) * minOverlapFraction))
        var bestS = 0
        var bestScore = Double.greatestFiniteMagnitude

        var s = 1
        while s <= h - minOverlap {
            let rows = h - s
            var sum = 0
            var count = 0
            // Sample every other row/column for speed.
            var r = 0
            while r < rows {
                let newBase = r * w
                let prevBase = (r + s) * w
                var c = 0
                while c < w {
                    let d = Int(new[newBase + c]) - Int(prev[prevBase + c])
                    sum += d < 0 ? -d : d
                    count += 1
                    c += 2
                }
                r += 2
            }
            let score = count > 0 ? Double(sum) / Double(count) : .greatestFiniteMagnitude
            if score < bestScore { bestScore = score; bestS = s }
            s += 1
        }
        // Reject weak matches (very different content = not a clean scroll).
        return bestScore < 24 ? bestS : nil
    }

    /// Render a CGImage to a top-origin grayscale byte buffer at `targetWidth`.
    private static func grayscale(_ image: CGImage, targetWidth: Int) -> ([UInt8], Int, Int) {
        let w = max(1, targetWidth)
        let h = max(1, Int((Double(image.height) / Double(max(image.width, 1))) * Double(w)))
        var data = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        data.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            // Flip so row 0 is the TOP of the image.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }
}
