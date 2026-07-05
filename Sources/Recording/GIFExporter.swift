import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import AppKit

/// Converts a recorded video into an animated GIF by sampling frames.
enum GIFExporter {
    /// Sample `fps` frames per second from the video and encode a looping GIF at `maxWidth`.
    static func convert(videoURL: URL, to gifURL: URL, fps: Int = 12, maxWidth: CGFloat = 720) async -> Bool {
        let asset = AVURLAsset(url: videoURL)
        guard let duration = try? await asset.load(.duration) else { return false }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds > 0 else { return false }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: maxWidth, height: 0)

        let frameDelay = 1.0 / Double(fps)
        var times: [NSValue] = []
        var t = 0.0
        while t < seconds {
            times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
            t += frameDelay
        }
        guard !times.isEmpty else { return false }

        guard let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString,
                                                         times.count, nil) else { return false }
        let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: frameDelay]]

        for value in times {
            if let cg = try? generator.copyCGImage(at: value.timeValue, actualTime: nil) {
                CGImageDestinationAddImage(dest, cg, frameProps as CFDictionary)
            }
        }
        return CGImageDestinationFinalize(dest)
    }
}
