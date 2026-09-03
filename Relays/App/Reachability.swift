//
//  Reachability.swift
//  Relays
//
//  Whether there is a way out at all. The app used to say the same thing about a
//  server that was down and a phone in a tunnel — "cannot reach the server" —
//  and those are not the same problem for the person holding it.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class Reachability {

    /// True until proven otherwise: a brand-new monitor has not answered yet,
    /// and showing "no connection" before knowing would be its own lie.
    private(set) var isOnline = true
    /// Moves every time the connection comes back, so views can reload on it.
    private(set) var restoredAt = 0

    private let monitor = NWPathMonitor()
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] path in
            let reachable = path.status == .satisfied
            Task { @MainActor in self?.apply(reachable) }
        }
        monitor.start(queue: DispatchQueue(label: "relays.reachability"))
    }

    private func apply(_ reachable: Bool) {
        guard reachable != isOnline else { return }
        isOnline = reachable
        if reachable { restoredAt += 1 }
    }

    /// For tests and previews, which have no business starting a monitor.
    func setOnlineForTesting(_ value: Bool) { apply(value) }
}
