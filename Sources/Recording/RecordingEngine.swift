import ScreenCaptureKit
import AVFoundation
import AppKit

/// Records a display to an H.264 MP4 using ScreenCaptureKit frames fed into AVAssetWriter.
/// Delegate callbacks arrive on a private queue, so the class synchronizes there and is
/// marked @unchecked Sendable rather than actor-isolated.
final class RecordingEngine: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var outputURL: URL?
    private var completion: ((URL?) -> Void)?

    private let queue = DispatchQueue(label: "me.ebnsina.SnapKeep.recording")

    /// Start recording the given display. `completion` fires (on the main thread) with the
    /// finished file URL, or nil on failure, after `stop()`.
    func start(displayID: CGDirectDisplayID, scale: Int, fps: Int, captureAudio: Bool = false) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        // Keep SnapKeep's own windows (the control bar) out of the recording.
        let ourApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter: SCContentFilter
        if let ourApp {
            filter = SCContentFilter(display: display, excludingApplications: [ourApp], exceptingWindows: [])
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }

        let width = display.width * scale
        let height = display.height * scale

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6
        if captureAudio {
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CaptureError.captureFailed("writer rejected input") }
        writer.add(input)

        if captureAudio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            aInput.expectsMediaDataInRealTime = true
            if writer.canAdd(aInput) { writer.add(aInput); self.audioInput = aInput }
        }

        self.outputURL = url
        self.writer = writer
        self.videoInput = input
        self.sessionStarted = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if captureAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        self.stream = stream
        try await stream.startCapture()
    }

    /// Stop recording and finalize the file, then call the completion set in `start`.
    func stop(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        guard let stream else { completion(nil); return }
        stream.stopCapture { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                self.writer?.finishWriting { [weak self] in
                    guard let self else { return }
                    let url = self.writer?.status == .completed ? self.outputURL : nil
                    let done = self.completion
                    self.completion = nil
                    self.stream = nil
                    self.writer = nil
                    self.videoInput = nil
                    self.audioInput = nil
                    DispatchQueue.main.async { done?(url) }
                }
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, let writer else { return }

        // Audio: only after the session has started (video establishes the timeline).
        if type == .audio {
            guard writer.status == .writing, let audio = audioInput, audio.isReadyForMoreMediaData else { return }
            audio.append(sampleBuffer)
            return
        }

        guard type == .screen, let input = videoInput else { return }
        // Only append complete frames (skip idle/blank status updates).
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw), status == .complete else { return }

        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            sessionStarted = true
        }
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("SnapKeep recording stopped with error: \(error.localizedDescription)")
    }
}
