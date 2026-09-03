//
//  PhoneTests.swift
//  RelaysTests
//
//  A phone number is the one field in the form that cannot be checked by
//  looking at it: what counts as a number depends on where the person is. And
//  the server that asks for one is not necessarily willing to use it —
//  bsky.social advertises `phoneVerificationRequired: true` and then answers
//  every request for a code with "phone verification not enabled". Both halves
//  are pinned here.
//

import Testing
import Foundation
@testable import Relays

@Suite("Phone numbers")
struct PhoneTests {

    // MARK: - The country in front

    @Test("The table carries the world, and the shared codes stay shared")
    func table() {
        #expect(DiallingCode.all.count > 200)
        #expect(DiallingCode.named("DE")?.code == "49")
        #expect(DiallingCode.named("AT")?.code == "43")
        #expect(DiallingCode.named("CH")?.code == "41")
        // One code, several countries — the table keeps the root rather than
        // inventing a per-country number that does not exist.
        #expect(DiallingCode.named("US")?.code == "1")
        #expect(DiallingCode.named("CA")?.code == "1")
        #expect(DiallingCode.named("RU")?.code == "7")
        #expect(DiallingCode.named("KZ")?.code == "7")

        // No duplicates, and nothing but digits.
        #expect(Set(DiallingCode.all.map(\.region)).count == DiallingCode.all.count)
        #expect(DiallingCode.all.allSatisfy { $0.code.allSatisfy(\.isNumber) })
    }

    @Test("A flag comes out of the letters, not a picture file")
    func flags() {
        #expect(DiallingCode.named("DE")?.flag == "🇩🇪")
        #expect(DiallingCode.named("JP")?.flag == "🇯🇵")
    }

    /// The trunk zero is the trap: it means "the rest of this country" and is
    /// wrong the moment a country code goes in front of it.
    @Test("Whatever a person types becomes one E.164 number",
          arguments: [("DE", "0151 12345678", "+4915112345678"),
                      ("DE", "+49 151 12345678", "+4915112345678"),
                      ("DE", "0049 151 12345678", "+4915112345678"),
                      // The number says Austria, the picker says Germany. The
                      // number wins — it is the more specific statement.
                      ("DE", "+43 664 1234567", "+436641234567"),
                      ("DE", "(0151) 1234-5678", "+4915112345678"),
                      ("AT", "0664 1234567", "+436641234567"),
                      ("US", "(415) 555-0123", "+14155550123")])
    func e164(_ region: String, _ typed: String, _ expected: String) {
        var draft = SignUpDraft()
        draft.phoneRegion = region
        draft.phone = typed
        #expect(draft.phoneE164 == expected)
    }

    @Test("An empty number stays empty rather than becoming a country code")
    func emptyStaysEmpty() {
        var draft = SignUpDraft()
        draft.phoneRegion = "DE"
        draft.phone = "   "
        #expect(draft.phoneE164 == "")
        #expect(!draft.phoneLooksLikeOne)
    }

    @Test("Length is checked against E.164's own bounds, not a guess")
    func length() {
        var draft = SignUpDraft()
        draft.phoneRegion = "DE"

        draft.phone = "123"                    // +49123 — six digits, too short
        #expect(!draft.phoneLooksLikeOne)

        draft.phone = "15112345678"
        #expect(draft.phoneLooksLikeOne)

        draft.phone = "151123456789012345"     // past fifteen
        #expect(!draft.phoneLooksLikeOne)
    }

    // MARK: - A server that contradicts itself

    private func blueskyLike() -> ServerDescription {
        var description = ServerDescription()
        description.phoneVerificationRequired = true
        description.availableUserDomains = [".bsky.social"]
        return description
    }

    private func filledDraft() -> SignUpDraft {
        var draft = SignUpDraft()
        draft.handle = "someone"
        draft.email = "someone@example.com"
        draft.password = "aLongEnoughOne"
        draft.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
        draft.acceptedTerms = true
        return draft
    }

    @Test("Without a code the form stays incomplete, as the server asked")
    func codeIsRequiredWhileTheServerMeansIt() {
        let draft = filledDraft()
        #expect(!draft.isComplete(for: blueskyLike()))
    }

    /// The live server answers `describeServer` with phoneVerificationRequired
    /// true and `com.atproto.temp.requestPhoneVerification` with HTTP 400,
    /// "phone verification not enabled". Without this the form can never be
    /// finished by anybody.
    @Test("A server that refuses to send codes stops requiring one")
    func refusalReleasesTheForm() {
        var draft = filledDraft()
        draft.phoneVerificationRefused = true
        #expect(draft.isComplete(for: blueskyLike()))
    }

    @Test("The refusal does not release anything else")
    func refusalIsNotABypass() {
        var draft = filledDraft()
        draft.phoneVerificationRefused = true
        draft.acceptedTerms = false
        #expect(!draft.isComplete(for: blueskyLike()))

        var young = filledDraft()
        young.phoneVerificationRefused = true
        young.birthDate = Calendar.current.date(byAdding: .year, value: -11, to: Date())!
        #expect(!young.isComplete(for: blueskyLike()))
    }
}
