import Foundation

/// Single source of truth for the product's identity. Change it here and the whole
/// runtime UI (menu, save folder, status text) updates. Build-level names live in
/// `project.yml` via `$(PRODUCT_NAME)` — keep the two in sync when rebranding.
enum Brand {
    static let name = "SnapKeep"
    static let tagline = "Capture · Annotate · Keep"

    /// Folder created under ~/Pictures for saved captures.
    static var saveFolderName: String { name }

    /// Prefix for timestamped capture filenames, e.g. "SnapKeep 2026-07-05 at 14.30.12.png".
    static var filePrefix: String { name }

    /// Marketing version, e.g. "0.1.0" (from Info.plist CFBundleShortVersionString).
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Build number (CFBundleVersion).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static let copyright = "© 2026 ebnsina · MIT Licensed"
}
