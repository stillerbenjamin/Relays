//
//  FeedRow.swift
//  Relays
//
//  One post as it appears in a list, and the rules for whether it appears at
//  all. Both were written out at each call site, and the profile's copy had
//  drifted: it left `repostedBy` out, so more than half of what a profile shows
//  — reposts — was drawn under the profile owner's name as if they had written
//  it. One row, one filter, no third copy to drift.
//

import SwiftUI

struct FeedRow: View {
    let item: FeedViewPost

    @Environment(\.navigate) private var navigate
    @Environment(\.composeAction) private var compose

    var body: some View {
        PostRowView(post: item.post,
                    repostedBy: item.repostedBy,
                    replyingTo: item.reply?.parent?.author,
                    onOpenThread: { navigate(.thread(uri: $0.uri)) },
                    onOpenProfile: { navigate(.profile(actor: $0.did)) },
                    onReply: { compose(ComposeTarget(replyTo: $0)) },
                    onOpenURI: { navigate(.thread(uri: $0)) },
                    onOpenQuotes: { navigate(.quotes(uri: $0.uri)) },
                    onOpenActors: { navigate(.actorList(subject: $0.uri, kind: $1)) })
    }
}

/// What a list leaves out, in the order that matters: moderation before the
/// device's own rules, so a block cannot be argued with locally.
///
/// There is deliberately no profile-specific variant. A muted account's posts
/// are already hidden by `AppModel.decision(for:)`, which runs before any list
/// sees them, so a list-level exemption would be dead code that reads as if it
/// worked.
enum FeedVisibility {

    @MainActor
    static func visible(_ posts: [FeedViewPost],
                        app: AppModel, settings: AppSettings) -> [FeedViewPost] {
        posts.filter { item in
            guard !app.isHidden(item.post.author.did) else { return false }
            guard !app.deletedPosts.contains(item.post.uri) else { return false }
            guard settings.passesFeedFilter(item) else { return false }
            guard !app.decision(for: item.post).hides else { return false }
            return app.rules.allows(item, origin: app.directory.origin(for: item.post.author.did))
        }
    }
}
