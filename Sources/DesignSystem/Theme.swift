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

    // MARK: Corner radius
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
        static let pill: CGFloat = 999
    }

    // MARK: Motion
    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.28)
        static let smooth: Animation = .smooth(duration: 0.35)
        static let bouncy: Animation = .bouncy(duration: 0.5, extraBounce: 0.15)
    }

    // MARK: Brand color — azure blue the whole app leans on.
    static let accent = Color(red: 0.18, green: 0.49, blue: 0.97)      // #2E7DF7
    static let accentSoft = Color(red: 0.35, green: 0.61, blue: 1.0)   // #5A9BFF

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.18, green: 0.49, blue: 0.97),  // #2E7DF7
                 Color(red: 0.12, green: 0.37, blue: 0.88)], // #1F5FE0
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// NSColor mirror of `accent`, for AppKit surfaces (overlay border, loupe ring).
    static let accentNS = NSColor(red: 0.18, green: 0.49, blue: 0.97, alpha: 1)
}

extension View {
    /// Standard translucent card used across menus and panels.
    func snapCard(radius: CGFloat = Theme.Radius.lg) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
