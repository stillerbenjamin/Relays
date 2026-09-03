//
//  HomeServerLine.swift
//  Relays
//
//  The line under the handle field on the sign-in screen.
//
//  Every other client asks for a handle and a password and tells you nothing
//  until you are inside. But the answer to "where does this account actually
//  live" is public, needs no password, and is the whole reason this app exists:
//  a handle resolves to a DID, the DID document names the server, and the relay
//  will say whether that server is up and how many accounts it holds.
//
//  So the app says it before you sign in. It is also a real check — a handle
//  that resolves to nothing says so here rather than after a password.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class HomeServerLookup {
    enum State: Equatable {
        case idle
        case looking
        /// Resolved, with whatever the relay could add about it.
        case found(host: String, status: RelayHost?)
        /// The identifier resolves to nothing the network knows.
        case unknown
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    /// Typing should not resolve on every keystroke, and a half-typed handle
    /// resolves to nothing anyway.
    func lookUp(_ identifier: String) {
        task?.cancel()
        let cleaned = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))

        guard Self.looksResolvable(cleaned) else {
            state = .idle
            return
        }

        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.state = .looking }

            guard let service = await PDSDirectory.resolveService(for: cleaned) else {
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.state = .unknown }
                return
            }
            let host = service
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.state = .found(host: host, status: nil) }

            // The relay's word is a bonus, not a requirement: a server it has
            // never heard of is still the server this account lives on.
            let status = try? await ATProtoClient.hostStatus(hostname: host)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.state = .found(host: host, status: status) }
        }
    }

    func cancel() {
        task?.cancel()
        state = .idle
    }

    /// A handle needs a dot, a DID needs its prefix. Anything else is somebody
    /// still typing. Pure, and deliberately not on the actor: this is the piece
    /// worth testing without a network.
    nonisolated static func looksResolvable(_ identifier: String) -> Bool {
        if identifier.hasPrefix("did:") { return identifier.count > 8 }
        guard identifier.contains(".") else { return false }
        let parts = identifier.split(separator: ".")
        return parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } && identifier.count >= 4
    }
}

/// One line, and it only appears when it has something to say.
struct HomeServerLine: View {
    let state: HomeServerLookup.State

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .looking:
            line {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Theme.Palette.textTertiary)
                Text(L(.authResolving))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

        case .unknown:
            line {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(Theme.Palette.textTertiary)
                Text(L(.authNotResolved))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }

        case .found(let host, let status):
            line {
                Circle()
                    .fill(status.map { HostsView.colour(for: $0.status ?? "") }
                          ?? Theme.Palette.hairline)
                    .frame(width: 6, height: 6)

                Text(host)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let status {
                    Text("·")
                        .foregroundStyle(Theme.Palette.hairline)
                    Text(HostsView.label(for: status.status ?? ""))
                        .foregroundStyle(Theme.Palette.textTertiary)
                    if status.accounts > 0 {
                        Text("·")
                            .foregroundStyle(Theme.Palette.hairline)
                        Text("\(Format.compact(status.accounts)) \(L(.hostsAccounts))")
                            .foregroundStyle(Theme.Palette.textTertiary)
                    }
                }
            }
        }
    }

    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            content()
            Spacer(minLength: 0)
        }
        .font(Theme.Font.mono(11))
        .padding(.horizontal, 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}
