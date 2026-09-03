//
//  BackgroundModeTests.swift
//  RelaysTests
//
//  A background mode is a promise to the system, and Apple checks it. The app
//  declared `remote-notification` for months with no APNs certificate, no
//  `aps-environment` entitlement and no app delegate to receive a token — a
//  routine review rejection, bought nothing, and nothing in the project would
//  have noticed.
//
//  Built like `PrivacyManifestTests`: it reads what actually ships.
//
//  iOS only. `UIBackgroundModes` and `BGTaskScheduler` are iOS keys — on macOS
//  the app keeps itself up to date by being open, and there is nothing declared
//  to check.
//

#if os(iOS)
import Testing
import Foundation
@testable import Relays

@Suite("Background modes")
struct BackgroundModeTests {

    private func plist() throws -> [String: Any] {
        try #require(Bundle.main.infoDictionary, "the app has no Info.plist")
    }

    private var modes: [String] {
        (Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String]) ?? []
    }

    /// Every mode the app claims has to be one it can actually use.
    @Test("Nothing is declared that the app cannot do")
    func declaredModesAreEarned() throws {
        let entitlements = Bundle.main.infoDictionary?["aps-environment"]
        for mode in modes {
            switch mode {
            case "fetch":
                // Earned by BGTaskScheduler, whose identifier is checked below.
                continue
            case "remote-notification":
                #expect(entitlements != nil,
                        "remote-notification is declared, but the app has no push entitlement")
            default:
                Issue.record("undeclared background mode reached the bundle: \(mode)")
            }
        }
    }

    /// The identifier in the plist and the one the code registers have to be the
    /// same string, or the task is never granted a turn and nothing says so.
    @Test("The background task's name matches the one it registers under")
    func identifierMatches() throws {
        let permitted = (Bundle.main.infoDictionary?["BGTaskSchedulerPermittedIdentifiers"]
                         as? [String]) ?? []
        #expect(permitted.contains(BackgroundRefresh.taskIdentifier),
                "BGTaskSchedulerPermittedIdentifiers does not list \(BackgroundRefresh.taskIdentifier)")
    }

    @Test("Background fetch is still declared — the app depends on it")
    func fetchIsThere() {
        #expect(modes.contains("fetch"))
    }
}
#endif
