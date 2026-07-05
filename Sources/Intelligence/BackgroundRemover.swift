@preconcurrency import Vision
import CoreImage
import CoreGraphics

/// Lifts the foreground subject out of a capture using Vision, returning the subject on a
/// transparent background. On-device (macOS 14+).
enum BackgroundRemover {
    static func removeBackground(from cgImage: CGImage) async -> CGImage? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNGenerateForegroundInstanceMaskRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    guard let result = request.results?.first else {
                        cont.resume(returning: nil); return
                    }
                    let masked = try result.generateMaskedImage(
                        ofInstances: result.allInstances, from: handler,
                        croppedToInstancesExtent: false)
                    let ci = CIImage(cvPixelBuffer: masked)
                    let out = CIContext().createCGImage(ci, from: ci.extent)
                    cont.resume(returning: out)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
