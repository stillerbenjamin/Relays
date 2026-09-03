//
//  FontLoader.swift
//  Relays
//
//  Registers any font files shipped in the bundle at launch. Doing it in code
//  keeps the generated Info.plist untouched and makes a missing file harmless:
//  the interface falls back to the system sans, which is close to Inter.
//

import Foundation
import CoreText

enum FontLoader {

    private static var didRegister = false

    /// Safe to call more than once; only the first call touches the font manager.
    @MainActor
    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        let names = ["Inter-Light", "Inter-Regular", "Inter-Medium", "Inter-SemiBold"]

        for name in names {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf")
                    ?? Bundle.main.url(forResource: name, withExtension: "otf") else { continue }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            error?.release()
        }
    }
}
