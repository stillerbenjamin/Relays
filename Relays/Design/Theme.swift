//
//  Theme.swift
//  Relays
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The grounds the app can stand on. Light, dim and dark follow the convention
/// Twitter set and Bluesky kept: a neutral surface with blue as an accent, never
/// as the field. Blue keeps the earlier full-bleed treatment as an option.
enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case light, dim, dark, blue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return L(.themeLight)
        case .dim: return L(.themeDim)
        case .dark: return L(.themeDark)
        case .blue: return L(.themeBlue)
        }
    }

    /// System chrome — keyboards, scrollbars — follows the ground's brightness.
    var colorScheme: ColorScheme { self == .light || self == .blue ? .light : .dark }
}

/// Central design constants.
enum Theme {

    /// Set from the settings; the interface is rebuilt when it changes.
    @MainActor static var theme: AppTheme = .dark

    // MARK: - Colours

    @MainActor
    enum Palette {
        /// Bluesky's blue, used the way Bluesky uses it: for what can be acted on.
        static let brand = Color(red: 0.0, green: 0.322, blue: 1.0)      // #0052FF-ish
        static let blueGround = Color(red: 0.0, green: 0.522, blue: 1.0) // #0085FF

        static var background: Color {
            switch Theme.theme {
            case .light: return .white
            case .dim: return Color(red: 0.082, green: 0.125, blue: 0.169)   // #15202B
            case .dark: return .black
            case .blue: return blueGround
            }
        }

        /// Cards, fields, muted fills.
        static var surface: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.949, green: 0.957, blue: 0.965) // #F2F4F6
            case .dim: return Color(red: 0.118, green: 0.153, blue: 0.196)
            case .dark: return Color(red: 0.086, green: 0.094, blue: 0.11)
            case .blue: return Color.black.opacity(0.13)
            }
        }

        static var surfaceRaised: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.898, green: 0.914, blue: 0.929)
            case .dim: return Color(red: 0.157, green: 0.196, blue: 0.243)
            case .dark: return Color(red: 0.133, green: 0.141, blue: 0.157)
            case .blue: return Color.black.opacity(0.22)
            }
        }

        /// The separator between posts — the single most recognisable piece of
        /// this layout family.
        static var hairline: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.878, green: 0.906, blue: 0.925)  // #E0E7EC
            case .dim: return Color(red: 0.22, green: 0.267, blue: 0.302)
            case .dark: return Color(red: 0.145, green: 0.157, blue: 0.169)
            case .blue: return Color.black.opacity(0.16)
            }
        }

        static var textPrimary: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.059, green: 0.078, blue: 0.098)  // #0F1419
            case .dim: return Color(red: 0.969, green: 0.976, blue: 0.976)
            case .dark: return Color(red: 0.906, green: 0.914, blue: 0.918)
            case .blue: return .black
            }
        }

        static var textSecondary: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.325, green: 0.392, blue: 0.443)  // #536471
            case .dim, .dark: return Color(red: 0.545, green: 0.596, blue: 0.647)
            case .blue: return Color.black.opacity(0.66)
            }
        }

        static var textTertiary: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.478, green: 0.545, blue: 0.596)
            case .dim, .dark: return Color(red: 0.443, green: 0.463, blue: 0.482)
            case .blue: return Color.black.opacity(0.45)
            }
        }

        /// The accent lightens on dark grounds — #0052FF is legible on white but
        /// sinks into black, which is why both Twitter and Bluesky shift it too.
        private static var tintedBrand: Color {
            switch Theme.theme {
            case .light: return brand
            case .dim, .dark: return Color(red: 0.29, green: 0.62, blue: 1.0)   // #4A9EFF
            case .blue: return .white
            }
        }

        /// Filled controls carry text in the background colour.
        static var accent: Color {
            Theme.theme == .blue ? .black : tintedBrand
        }

        static var onAccent: Color {
            switch Theme.theme {
            case .blue: return blueGround
            case .dim, .dark: return .black
            case .light: return .white
            }
        }

        static var link: Color { tintedBrand }

        /// Interaction colours, kept apart from the accent — the convention this
        /// layout family established and readers already know.
        static var like: Color {
            Theme.theme == .blue ? .white : Color(red: 0.976, green: 0.094, blue: 0.502)  // #F91880
        }

        static var repost: Color {
            Theme.theme == .blue ? .white : Color(red: 0.0, green: 0.729, blue: 0.486)    // #00BA7C
        }

        static var danger: Color {
            switch Theme.theme {
            case .light: return Color(red: 0.784, green: 0.157, blue: 0.196)
            case .dim, .dark: return Color(red: 0.90, green: 0.29, blue: 0.31)
            case .blue: return Color(red: 0.33, green: 0.02, blue: 0.05)
            }
        }

        /// Full-screen media always sits on black, so this pair stays fixed.
        static let onMedia = Color.white
        static let mediaScrim = Color.black.opacity(0.55)
    }

    // MARK: - Typography

    @MainActor
    enum Font {
        static var scale: CGFloat = 1.0
        static var slim: Bool = true
        static var dynamicScale: CGFloat = 1.0

        /// Inter, the face Bluesky itself uses; the system sans stands in if the
        /// bundled files are ever missing.
        static func ui(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            let points = (size * scale * dynamicScale).rounded()
            let applied = thinned(weight)
            if hasInter {
                return .custom(interName(for: applied), size: points)
            }
            return .system(size: points, weight: applied)
        }

        /// Data — DIDs, AT URIs, counters — in the same face, with tabular figures
        /// so columns of numbers still line up.
        static func mono(_ size: CGFloat, _ weight: SwiftUI.Font.Weight = .regular) -> SwiftUI.Font {
            ui(size, weight).monospacedDigit()
        }

        /// Slimming applies to display sizes only. Body text at reading size stays
        /// at its drawn weight, which is what keeps this layout legible.
        private static func thinned(_ weight: SwiftUI.Font.Weight) -> SwiftUI.Font.Weight {
            guard slim else { return weight }
            switch weight {
            case .semibold: return .medium
            case .medium: return .regular
            default: return weight
            }
        }

        static let hasInter: Bool = {
            FontLoader.registerBundledFonts()
            #if canImport(UIKit)
            return UIFont(name: "Inter-Regular", size: 12) != nil
            #else
            return NSFont(name: "Inter-Regular", size: 12) != nil
            #endif
        }()

        private static func interName(for weight: SwiftUI.Font.Weight) -> String {
            switch weight {
            case .ultraLight, .thin, .light: return "Inter-Light"
            case .medium: return "Inter-Medium"
            case .semibold, .bold, .heavy, .black: return "Inter-SemiBold"
            default: return "Inter-Regular"
            }
        }

        static var wordmark: SwiftUI.Font { ui(25, .semibold) }
        static var title: SwiftUI.Font { ui(17, .semibold) }
        /// Post text sits at reading size, as in the apps this follows.
        static var body: SwiftUI.Font { ui(15) }
        static var caption: SwiftUI.Font { ui(13) }
        static var micro: SwiftUI.Font { ui(11) }
        static var tab: SwiftUI.Font {
            hasInter ? .custom("Inter-Medium", size: 10) : .system(size: 10, weight: .medium)
        }
    }

    // MARK: - Metrics

    enum Metric {
        static let fieldHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 10
        static let hPadding: CGFloat = 16
        static let wordmarkTracking: CGFloat = 0.5
        /// Avatar column width in the timeline; the text column starts after it.
        static let avatar: CGFloat = 44
        static let avatarGap: CGFloat = 12
    }
}

extension View {
    @MainActor
    func relaysBackground() -> some View {
        #if os(iOS)
        return background(Theme.Palette.background.ignoresSafeArea())
        #else
        return background(Theme.Palette.background)
        #endif
    }

    /// A menu whose label is already drawn by the app. Without this, macOS gives
    /// it a bordered pop-up button with a chevron, which is why the repost
    /// control looked like a form field.
    @MainActor
    /// How big a sheet should be.
    ///
    /// `presentationDetents` is iOS-only. On macOS a sheet takes the size of its
    /// content — and content built on a `ScrollView` or a `TextEditor` has no
    /// size of its own, so the sheet collapses to its header and footer. The two
    /// platforms need different sentences for the same intent.
    func sheetSize(_ size: SheetSize = .large) -> some View {
        #if os(macOS)
        return frame(minWidth: size.minWidth, idealWidth: size.idealWidth,
                     minHeight: size.minHeight, idealHeight: size.idealHeight)
        #else
        return presentationDetents(size.detents)
        #endif
    }

    func plainMenu() -> some View {
        #if os(macOS)
        return self
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        #else
        return self
        #endif
    }

    /// Keeps the app at a reading width in a window that can be made as wide as
    /// a desk. On iPhone the screen is already the column and nothing changes.
    @MainActor
    func readingColumn() -> some View {
        #if os(macOS)
        self
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    @MainActor
    func relaysColorScheme() -> some View {
        preferredColorScheme(Theme.theme.colorScheme)
    }
}


/// The sizes sheets come in. Named rather than numeric so the two platforms can
/// disagree about what the number is.
enum SheetSize {
    case large
    case medium
    /// A sheet whose content really does have one height, like the alt-text one.
    case fixed(CGFloat)

    var detents: Set<PresentationDetent> {
        switch self {
        case .large: return [.large]
        case .medium: return [.medium, .large]
        case .fixed(let height): return [.height(height)]
        }
    }

    var minWidth: CGFloat { 460 }
    var idealWidth: CGFloat { 560 }

    var minHeight: CGFloat {
        switch self {
        case .large: return 480
        case .medium: return 380
        case .fixed(let height): return height
        }
    }

    var idealHeight: CGFloat {
        switch self {
        case .large: return 660
        case .medium: return 480
        case .fixed(let height): return height
        }
    }
}
