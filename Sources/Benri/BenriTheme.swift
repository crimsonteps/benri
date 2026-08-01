import SwiftUI

enum BenriTheme {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 20
    }

    enum Radius {
        static let panel: CGFloat = 24
        static let contentPanel: CGFloat = 22
        static let row: CGFloat = 10
        static let card: CGFloat = 12
        static let floatingControl: CGFloat = 16
    }

    enum Size {
        static let searchHeaderHeight: CGFloat = 54
        static let rowIcon: CGFloat = 26
        static let floatingButton: CGFloat = 36
    }

    enum Typography {
        static let search = Font.system(size: 18, weight: .regular)
        static let rowTitle = Font.body.weight(.medium)
        static let rowDetail = Font.caption
        static let preview = Font.system(.subheadline, design: .monospaced)
    }

    enum Colors {
        static func panelTint(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.black.opacity(0.40) : Color.white.opacity(0.42)
        }

        static func selection(for scheme: ColorScheme, active: Bool = true) -> Color {
            if scheme == .dark {
                return Color.white.opacity(active ? 0.11 : 0.075)
            }
            return Color.black.opacity(active ? 0.085 : 0.055)
        }

        static func rowHover(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.04)
        }

        static func border(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
        }

        static func separator(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        }

        static func cardFill(for scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.035)
        }
    }
}
