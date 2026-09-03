//
//  VerificationBadge.swift
//  Relays
//
//  The mark next to a name. It takes its colour from the palette, so it reads on
//  every ground the app offers — blue on light and dark, white on the blue one.
//

import SwiftUI

struct VerificationBadge: View {
    let verification: VerificationState?
    var size: CGFloat = 15

    @Environment(AppSettings.self) private var settings

    private enum Kind {
        case verified, trustedVerifier

        /// A scalloped seal for those who verify others, a plain circle for those
        /// who were verified — the same distinction the network draws.
        var symbol: String {
            switch self {
            case .verified: return "checkmark.circle.fill"
            case .trustedVerifier: return "checkmark.seal.fill"
            }
        }

        var label: String {
            switch self {
            case .verified: return L(.verified)
            case .trustedVerifier: return L(.trustedVerifier)
            }
        }
    }

    private var kind: Kind? {
        guard let verification else { return nil }
        if verification.isTrustedVerifier { return .trustedVerifier }
        if verification.isVerified { return .verified }
        return nil
    }

    var body: some View {
        if let kind {
            Image(systemName: kind.symbol)
                .font(.system(size: size))
                .foregroundStyle(Theme.Palette.link)
                .accessibilityLabel(kind.label)
        }
    }
}
