//
//  SignUp.swift
//  Relays
//
//  Making an account. What a server asks for is not the same everywhere — one
//  wants an invite code, another a phone number, a third neither — so the form
//  is built from what the server says about itself rather than from what Bluesky
//  happens to require today.
//
//  The real account password lives in `SignUpDraft` for the length of one call
//  and is never stored. What ends up in the keychain is an app password the app
//  makes for itself straight afterwards.
//

import Foundation

/// The fields, and whether they are enough yet.
struct SignUpDraft: Equatable {
    var host: String = ServerDescription.defaultHost
    var handle: String = ""
    var email: String = ""
    var password: String = ""
    var inviteCode: String = ""
    /// The country in front of the number. A bare national number means nothing
    /// to a server that has to send an actual message to it.
    var phoneRegion: String = DiallingCode.current.region
    var phone: String = ""
    var phoneCode: String = ""
    /// Set when the server said it wants a phone number and then refused to send
    /// a code. `bsky.social` does exactly this. See `SignUpView.sendPhoneCode`.
    var phoneVerificationRefused = false
    var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    var acceptedTerms = false

    /// The handle as the server will see it: what was typed, plus the server's
    /// own suffix unless the typist already brought a domain.
    func fullHandle(on description: ServerDescription?) -> String {
        let typed = handle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard !typed.isEmpty else { return "" }
        guard let suffix = description?.handleSuffix, !suffix.isEmpty else { return typed }
        return typed.contains(".") ? typed : typed + suffix
    }

    /// Eight is what the protocol asks for; anything shorter is refused by the
    /// server, and being told that after filling in a form is no way to find out.
    var passwordIsLongEnough: Bool { password.count >= 8 }

    /// Not validation of an address — only that something plausible was typed.
    var emailLooksLikeOne: Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !email.hasSuffix(".")
    }

    var dialling: DiallingCode {
        DiallingCode.named(phoneRegion) ?? DiallingCode.current
    }

    /// E.164: a plus, the country's code, then the number, with everything a
    /// person might type in it taken back out — spaces, dashes, brackets.
    ///
    /// Three ways of writing the same number have to arrive at one answer. A
    /// number that already carries its country, written either way people write
    /// it, keeps the country it carries — the picker is for the case where the
    /// number does not say. And a leading zero is a trunk code: it means "the
    /// rest of this country" and is wrong the moment a country code goes in
    /// front of it.
    var phoneE164: String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return "" }

        if trimmed.hasPrefix("+") { return "+" + digits }
        if digits.hasPrefix("00") { return "+" + digits.dropFirst(2) }

        let national = digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
        guard !national.isEmpty else { return "" }
        return dialling.prefix + national
    }

    /// The shortest real number in the world is eight digits including the
    /// country code, the longest fifteen. That is the whole of what can be
    /// checked without a table of every national numbering plan.
    var phoneLooksLikeOne: Bool {
        let digits = phoneE164.dropFirst().count
        return digits >= 8 && digits <= 15
    }

    /// Thirteen is the floor the network itself sets.
    var isOldEnough: Bool {
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 0
        return years >= 13
    }

    func isComplete(for description: ServerDescription?) -> Bool {
        // A server that could not be described has not told us what it wants, so
        // the form cannot know whether it is complete. Sending anyway would trade
        // a plain "this server does not answer" for a network error after a wait.
        guard description != nil else { return false }
        guard !fullHandle(on: description).isEmpty,
              emailLooksLikeOne, passwordIsLongEnough, isOldEnough, acceptedTerms
        else { return false }
        if description?.needsInviteCode == true, inviteCode.isEmpty { return false }
        // A server that asks for a phone number and then will not send a code
        // has answered the question itself.
        if description?.needsPhone == true, !phoneVerificationRefused,
           phoneCode.isEmpty { return false }
        return true
    }
}
