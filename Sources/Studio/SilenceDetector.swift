import AVFoundation

/// Scans a recording's audio and returns the time ranges worth keeping — i.e. everything except
/// silent gaps longer than `minSilence`. Used by the Studio's "Remove Silences".
enum SilenceDetector {
    static func loudRanges(url: URL, threshold: Double = 0.015,
                           minSilence: Double = 0.35, pad: Double = 0.08) async -> [CMTimeRange] {
        let asset = AVURLAsset(url: url)
        let dur = ((try? await asset.load(.duration)) ?? .zero)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return [CMTimeRange(start: .zero, duration: dur)]
        }
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }

        let sampleRate = 16000.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        reader.startReading()

        let windowLen = Int(sampleRate * 0.02) // 20ms windows
        var loudFlags: [Bool] = []
        var pending: [Int16] = []

        while reader.status == .reading, let sb = output.copyNextSampleBuffer() {
            if let bb = CMSampleBufferGetDataBuffer(sb) {
                var length = 0
                var dataPtr: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil,
                                            totalLengthOut: &length, dataPointerOut: &dataPtr)
                if let dataPtr {
                    let count = length / 2
                    dataPtr.withMemoryRebound(to: Int16.self, capacity: count) { p in
                        pending.append(contentsOf: UnsafeBufferPointer(start: p, count: count))
                    }
                }
            }
            CMSampleBufferInvalidate(sb)

            while pending.count >= windowLen {
                var sum = 0.0
                for i in 0..<windowLen { let f = Double(pending[i]) / 32768.0; sum += f * f }
                loudFlags.append(sqrt(sum / Double(windowLen)) >= threshold)
                pending.removeFirst(windowLen)
            }
        }
        guard !loudFlags.isEmpty else { return [CMTimeRange(start: .zero, duration: dur)] }

        return coalesce(loudFlags, window: 0.02, minSilence: minSilence, pad: pad, total: dur)
    }

    /// Turn per-window loud flags into keep-ranges: silent runs shorter than `minSilence` are
    /// kept; longer ones are cut, with `pad` seconds preserved on each side.
    private static func coalesce(_ flags: [Bool], window: Double, minSilence: Double,
                                 pad: Double, total: CMTime) -> [CMTimeRange] {
        var keep = flags
        var i = 0
        while i < flags.count {
            if flags[i] { i += 1; continue }
            var j = i
            while j < flags.count, !flags[j] { j += 1 }
            let runSeconds = Double(j - i) * window
            if runSeconds >= minSilence {
                let padWindows = Int(pad / window)
                for k in i..<j { keep[k] = false }
                for k in i..<min(i + padWindows, j) { keep[k] = true }
                for k in max(j - padWindows, i)..<j { keep[k] = true }
            } else {
                for k in i..<j { keep[k] = true } // brief pause — keep
            }
            i = j
        }

        var ranges: [CMTimeRange] = []
        var runStart: Int?
        for k in 0...keep.count {
            let on = k < keep.count && keep[k]
            if on, runStart == nil { runStart = k }
            if !on, let s = runStart {
                let start = Double(s) * window
                let end = min(Double(k) * window, total.seconds)
                if end > start {
                    ranges.append(CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                              duration: CMTime(seconds: end - start, preferredTimescale: 600)))
                }
                runStart = nil
            }
        }
        return ranges
    }
}
