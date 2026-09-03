//
//  Format.swift
//  Relays
//
//  Numbers the way the chosen language writes them. The app carries its own
//  language switch, so a German interface has to read "1,2k" and "18.402" even
//  on an English device — and an English one "1.2k" and "18,402" on a German
//  device. Anything formatted against `Locale.current` gets this wrong.
//

import Foundation

enum Format {

    /// The locale everything user-visible is formatted in.
    static var locale: Locale {
        Locale(identifier: L10n.language.resolved == .de ? "de_DE" : "en_US")
    }

    /// Counts, shortened so a long number cannot push a row apart.
    /// `fullBelow` is the point up to which the number is written out.
    static func compact(_ value: Int, fullBelow: Int = 1_000) -> String {
        switch value {
        case ..<0: return "0"
        case ..<fullBelow: return "\(value)"
        case ..<1_000_000:
            return String(format: "%.1fk", locale: locale, Double(value) / 1_000)
        default:
            return String(format: "%.1fM", locale: locale, Double(value) / 1_000_000)
        }
    }

    /// Counts that run into the tens of thousands. Ungrouped they stop being
    /// readable at a glance.
    static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
