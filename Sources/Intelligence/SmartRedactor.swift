@preconcurrency import Vision
import CoreGraphics
import Foundation

/// Finds sensitive regions to redact — faces, email addresses, and card-like number runs —
/// on-device via the Vision framework. Returns normalized rects (0–1, bottom-left origin).
enum SmartRedactor {
    static func detect(in cgImage: CGImage) async -> [CGRect] {
        await withCheckedContinuation { (cont: CheckedContinuation<[CGRect], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var rects: [CGRect] = []

                let faceReq = VNDetectFaceRectanglesRequest()
                let textReq = VNRecognizeTextRequest()
                textReq.recognitionLevel = .accurate

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([faceReq, textReq])

                for obs in (faceReq.results ?? []) { rects.append(obs.boundingBox) }

                let email = try? NSRegularExpression(
                    pattern: "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", options: [.caseInsensitive])
                // 13–19 digit runs (cards), allowing spaces/dashes between digits.
                let card = try? NSRegularExpression(pattern: "(?:\\d[ -]?){13,19}")

                for obs in (textReq.results ?? []) {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let s = candidate.string
                    let full = NSRange(s.startIndex..., in: s)
                    let matches = (email?.matches(in: s, range: full) ?? [])
                        + (card?.matches(in: s, range: full) ?? [])
                    for m in matches {
                        if let r = Range(m.range, in: s),
                           let box = try? candidate.boundingBox(for: r) {
                            rects.append(box.boundingBox)
                        }
                    }
                }

                cont.resume(returning: rects)
            }
        }
    }
}
