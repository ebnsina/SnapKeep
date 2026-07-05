import SwiftUI

/// User preferences, persisted in UserDefaults. Kept small and observable so both the
/// Settings window and the capture pipeline read from one place.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    enum ImageFormat: String, CaseIterable, Identifiable {
        case png, jpeg
        var id: String { rawValue }
        var ext: String { self == .png ? "png" : "jpg" }
        var title: String { self == .png ? "PNG" : "JPEG" }
    }

    private let defaults = UserDefaults.standard

    var format: ImageFormat {
        didSet { defaults.set(format.rawValue, forKey: "format") }
    }
    /// Seconds to wait before a capture (0 = immediate).
    var captureDelay: Int {
        didSet { defaults.set(captureDelay, forKey: "captureDelay") }
    }
    /// Copy to clipboard automatically on every capture.
    var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: "autoCopy") }
    }
    /// Custom save directory bookmark path; empty means ~/Pictures/SnapKeep.
    var saveDirectoryPath: String {
        didSet { defaults.set(saveDirectoryPath, forKey: "saveDirectoryPath") }
    }
    /// Play the classic shutter sound on capture.
    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }

    private init() {
        format = ImageFormat(rawValue: defaults.string(forKey: "format") ?? "png") ?? .png
        captureDelay = defaults.integer(forKey: "captureDelay")
        autoCopy = defaults.object(forKey: "autoCopy") as? Bool ?? true
        saveDirectoryPath = defaults.string(forKey: "saveDirectoryPath") ?? ""
        playSound = defaults.object(forKey: "playSound") as? Bool ?? true
    }

    var saveDirectory: URL {
        if !saveDirectoryPath.isEmpty {
            return URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
        }
        return CaptureStore.defaultDirectory
    }
}
