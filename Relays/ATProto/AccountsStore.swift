//
//  AccountsStore.swift
//  Relays
//
//  Several accounts, possibly on different servers, held together in the keychain.
//

import Foundation

struct StoredAccounts: Codable {
    var accounts: [StoredSession]
    var activeDID: String?

    var active: StoredSession? {
        accounts.first { $0.session.did == activeDID } ?? accounts.first
    }
}

enum AccountsStore {
    private static let account = "accounts"

    static func load() -> StoredAccounts {
        guard let data = Keychain.load(account: account),
              let stored = try? JSONDecoder().decode(StoredAccounts.self, from: data) else {
            return migrateLegacy()
        }
        return stored
    }

    static func save(_ accounts: StoredAccounts) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        Keychain.save(data, account: account)
    }

    static func clear() {
        Keychain.delete(account: account)
        Keychain.delete(account: "current")
    }

    /// Picks up a session written by the earlier single-account build.
    private static func migrateLegacy() -> StoredAccounts {
        guard let data = Keychain.load(account: "current"),
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            return StoredAccounts(accounts: [], activeDID: nil)
        }
        let migrated = StoredAccounts(accounts: [session], activeDID: session.session.did)
        save(migrated)
        Keychain.delete(account: "current")
        return migrated
    }
}
