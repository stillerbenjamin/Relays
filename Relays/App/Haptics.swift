//
//  Haptics.swift
//  Relays
//

#if canImport(UIKit) && os(iOS)
import UIKit
#endif

/// Light impact feedback for interactions; a no-op where the platform has no haptics.
enum Haptics {
    @MainActor
    static func tap(enabled: Bool) {
        guard enabled else { return }
        #if canImport(UIKit) && os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}
