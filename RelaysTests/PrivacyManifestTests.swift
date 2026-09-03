//
//  PrivacyManifestTests.swift
//  RelaysTests
//
//  The manifest is a file nothing in the app reads, so nothing in the app would
//  notice it going missing or going wrong. Apple would, at the worst moment.
//

import Testing
import Foundation
@testable import Relays

@Suite("Privacy manifest")
struct PrivacyManifestTests {

    private func manifest() throws -> [String: Any] {
        // The test bundle runs inside the app, so the app's own bundle is the
        // one that has to carry the file.
        let url = try #require(Bundle.main.url(forResource: "PrivacyInfo",
                                               withExtension: "xcprivacy"),
                               "PrivacyInfo.xcprivacy is not in the app bundle")
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(parsed as? [String: Any])
    }

    @Test("It ships with the app and parses")
    func present() throws {
        let plist = try manifest()
        #expect(plist["NSPrivacyTracking"] as? Bool == false)
        #expect((plist["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)
    }

    /// `UserDefaults` is the one interface with a required reason that the app
    /// touches. Adding another — file timestamps, free disk space, system uptime
    /// — without declaring it is a rejection.
    @Test("UserDefaults is declared, with the reason that fits")
    func userDefaults() throws {
        let plist = try manifest()
        let apis = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])

        let entry = try #require(apis.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults"
        })
        let reasons = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
        // CA92.1: only values the app itself wrote.
        #expect(reasons == ["CA92.1"])
    }

    @Test("Everything declared is for making the app work, and none of it tracks")
    func collectedData() throws {
        let plist = try manifest()
        let types = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])

        #expect(!types.isEmpty)
        for entry in types {
            let name = try #require(entry["NSPrivacyCollectedDataType"] as? String)
            #expect(name.hasPrefix("NSPrivacyCollectedDataType"), "odd type: \(name)")
            #expect(entry["NSPrivacyCollectedDataTypeTracking"] as? Bool == false,
                    "\(name) is marked as tracking")

            let purposes = try #require(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])
            #expect(purposes == ["NSPrivacyCollectedDataTypePurposeAppFunctionality"],
                    "\(name) claims a purpose the app does not have")
        }
    }

    /// The four kinds the app actually sends somewhere. If a feature starts
    /// sending something else, this is where it has to be said.
    @Test("What the app carries is all named")
    func coversWhatTheAppSends() throws {
        let plist = try manifest()
        let types = try #require(plist["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let declared = Set(types.compactMap { $0["NSPrivacyCollectedDataType"] as? String })

        #expect(declared.contains("NSPrivacyCollectedDataTypeEmailAddress"))      // sign-up
        #expect(declared.contains("NSPrivacyCollectedDataTypePhoneNumber"))       // verification
        #expect(declared.contains("NSPrivacyCollectedDataTypePhotosorVideos"))    // attachments
        #expect(declared.contains("NSPrivacyCollectedDataTypeOtherUserContent"))  // posts
        #expect(declared.contains("NSPrivacyCollectedDataTypeEmailsOrTextMessages")) // messages
    }
}
