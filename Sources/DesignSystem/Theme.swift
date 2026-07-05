import SwiftUI

/// Aperi design tokens — spacing, radius, motion, and colors.
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

    // MARK: Brand color — a modern indigo→violet the whole app leans on.
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.96)
    static let accentSoft = Color(red: 0.55, green: 0.50, blue: 0.98)

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.42, green: 0.36, blue: 0.96),
                 Color(red: 0.62, green: 0.34, blue: 0.90)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
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
