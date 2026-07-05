@preconcurrency import Vision
import AppKit

/// On-device OCR via the Vision framework. Nothing leaves the machine.
enum TextRecognizer {
    /// Recognize text in an image, returning the lines joined top-to-bottom. Empty if none.
    static func recognize(in cgImage: CGImage) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    // Vision returns observations bottom-up; sort by descending Y for reading order.
                    let lines = observations
                        .sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
