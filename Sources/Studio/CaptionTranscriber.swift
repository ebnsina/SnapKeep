@preconcurrency import Speech
import Foundation

/// A timed caption line.
struct Caption: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let start: Double
    let end: Double
}

/// On-device speech-to-text that groups words into short caption lines with timestamps.
enum CaptionTranscriber {
    static func authorize() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(url: URL, wordsPerLine: Int = 7) async -> [Caption] {
        guard await authorize(), let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return [] }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        let once = Once()
        return await withCheckedContinuation { (cont: CheckedContinuation<[Caption], Never>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    once.run { cont.resume(returning: []) }
                    _ = error
                    return
                }
                guard let result, result.isFinal else { return }
                let segments = result.bestTranscription.segments
                var lines: [Caption] = []
                var bucket: [SFTranscriptionSegment] = []
                func flush() {
                    guard let first = bucket.first, let last = bucket.last else { return }
                    let text = bucket.map { $0.substring }.joined(separator: " ")
                    lines.append(Caption(text: text, start: first.timestamp,
                                         end: last.timestamp + last.duration))
                    bucket.removeAll()
                }
                for s in segments {
                    bucket.append(s)
                    if bucket.count >= wordsPerLine { flush() }
                }
                flush()
                once.run { cont.resume(returning: lines) }
            }
        }
    }

    /// Guards a continuation against double-resume (the recognition callback can fire twice).
    private final class Once: @unchecked Sendable {
        private var done = false
        private let lock = NSLock()
        func run(_ block: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            if !done { done = true; block() }
        }
    }
}
