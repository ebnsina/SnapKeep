import SwiftUI

/// SnapKeep design tokens — spacing, radius, motion, and colors.
/// Keep everything routed through here so the whole app stays visually consistent.
enum Theme {
    // MARK: Spacing (4 / 8 pt scale)
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Corner radius — Tailwind-style scale, centered on rounded-xl (12).
    enum Radius {
        static let sm: CGFloat = 8    // rounded-lg
        static let md: CGFloat = 12   // rounded-xl (default surface radius)
        static let lg: CGFloat = 16   // rounded-2xl
        static let xl: CGFloat = 20   // rounded-3xl-ish
        static let pill: CGFloat = 999
    }

    // MARK: Motion — interactive springs tuned to feel light and responsive.
    enum Motion {
        /// Quick hover/tap feedback. Response low, well-damped (no wobble).
        static let snappy: Animation = .spring(response: 0.26, dampingFraction: 0.78)
        /// General transitions between states.
        static let smooth: Animation = .spring(response: 0.38, dampingFraction: 0.82)
        /// The Dynamic-Island-style expand: springy with a touch of overshoot.
        static let island: Animation = .spring(response: 0.42, dampingFraction: 0.68)
        static let bouncy: Animation = .spring(response: 0.5, dampingFraction: 0.6)
    }

    // MARK: Brand color — Honolulu Blue the whole app leans on.
    static let accent = Color(red: 0.0, green: 0.463, blue: 0.714)      // #0076B6
    static let accentSoft = Color(red: 0.13, green: 0.60, blue: 0.85)   // #2199D9

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.0, green: 0.463, blue: 0.714),  // #0076B6
                 Color(red: 0.0, green: 0.353, blue: 0.549)], // #005A8C
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// NSColor mirror of `accent`, for AppKit surfaces (overlay border, loupe ring).
    static let accentNS = NSColor(red: 0.0, green: 0.463, blue: 0.714, alpha: 1)
}

extension View {
    /// Standard translucent card used across menus and panels (rounded-xl by default).
    func snapCard(radius: CGFloat = Theme.Radius.md) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
