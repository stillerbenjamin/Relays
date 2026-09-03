//
//  L10n.swift
//  Relays
//
//  Hand-rolled localisation instead of a string catalog: the language can be
//  switched in settings and takes effect immediately, without an app restart.
//

import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system, de, en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L10n.t(.settingsLanguageSystem)
        case .de: return "Deutsch"
        case .en: return "English"
        }
    }

    /// The language actually in use — `system` follows the device language.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("de") ? .de : .en
    }
}

enum LKey: String, CaseIterable {
    case tabMessages, messagesEmpty, messagePlaceholder
    case newMessage, newMessageSearch, newMessageHint
    // Sign-in
    case authIdentifier, authPassword, authConnect

    // Navigation
    case tabFeed, tabSearch, tabNotifications, tabProfile
    case titleThread, titleSettings

    // Feed
    case feedEmpty, feedRepostedBy, retry, loadingImages, feedFollowing, replyingTo

    // Composing
    case composePlaceholder, composeReplyPlaceholder, composeReplyTo
    case composeAddImages, composeRemoveImage, composeAddAlt, composeImageFailed
    case composeAltTitle, composeAltPlaceholder, composeAltHint
    case composeAddVideo, composeVideoFailed, composeVideoTooLarge, composeVideoProgress
    case cancel, send

    // Profile
    case statFollowers, statFollowing, statPosts, profileEmpty, actorListEmpty
    case sectionReplies, sectionMedia
    case follow, unfollow, unfollowAction, verified, trustedVerifier

    // Moderation
    case moderationReport, moderationMute, moderationUnmute, moderationBlock, moderationUnblock
    case moderationDelete, moderationDeleteQuestion, moderationBlocked, moderationMuted
    case reportPost, reportAccount, reportNote, reportSend, reportSent
    case reportSpam, reportViolation, reportMisleading, reportSexual, reportRude, reportOther

    // Editing one's own profile
    case editProfile, editName, editAbout, editAvatar, editBanner, editTooLong, save
    case signOut, signOutQuestion

    // Notifications
    case notificationsEmpty
    case verbLike, verbRepost, verbFollow, verbMention, verbReply, verbQuote
    // The rest of the thirteen the protocol names. Missing ones used to show
    // the raw lexicon token to the reader.
    case verbLikeViaRepost, verbRepostViaRepost, verbStarterpackJoined
    case verbVerified, verbUnverified, verbSubscribedPost, verbContactMatch
    case verbUnknown
    case notifyMore, verbStarterpackNamed
    // The account's own notification settings
    case notifyKinds, notifyKindsHint, notifyAudience, notifyAudienceAll
    case notifyAudienceFollows, notifyAudienceMixed
    case notifyOff, notifyListOnly, notifyAlert
    case notifyGroupPosts, notifyGroupAccount, notifyGroupSubscriptions
    case notifyKindReply, notifyKindMention, notifyKindQuote, notifyKindLike
    case notifyKindRepost, notifyKindLikeViaRepost, notifyKindRepostViaRepost
    case notifyKindFollow, notifyKindVerified, notifyKindUnverified
    case notifyKindStarterpack, notifyKindSubscribed, notifySubscriptionsHint

    // Search
    case searchPlaceholder, searchEmpty, searchHint, searchPeople, searchPosts
    case hashtagEmpty

    // Settings
    case settingsAppearance, settingsFeed, settingsBehavior
    case settingsLanguage, settingsLanguageSystem
    case settingsTextSize, settingsTextSizeSmall, settingsTextSizeMedium, settingsTextSizeLarge
    case settingsSlimFonts, settingsShowImages, settingsAbsoluteTime
    case settingsCompact, settingsAltBadge, settingsCounts
    case settingsHideReposts, settingsHideReplies, settingsAutoRefresh
    case settingsOpenInApp, settingsHaptics, settingsShowOrigin, settingsDynamicType
    case settingsNotifications, notifyEnabled, notifyLikes, notifyReposts, notifyFollows
    case notifyReplies, notifyDenied, notifyHint
    case settingsTheme, themeLight, themeDim, themeDark, themeBlue
    case settingsTypeface, settingsSystemFace
    case actionReply, actionRepost, actionLike, actionUnlike, actionUndoRepost, actionQuote

    // Inspector and media
    case inspectorTitle, inspectorAuthor, inspectorDID, inspectorPDS, inspectorURI
    case inspectorCID, inspectorCreated, inspectorIndexed, inspectorFacets, inspectorRecord
    case close, copied, video, videoUnavailable, inspect, hostedOn
    case imagePrevious, imageNext, imageCount, refresh
    // Embedded records that are not a quoted post
    case embedFeed, embedList, embedStarterPack, embedNotFound, embedBlocked
    case embedDetached, embedJoined, embedLikes
    case likesTitle, repostsTitle, postListEmpty, seeLikes, seeReposts
    // The relay's register of servers
    case hostsTitle, hostsHint, hostsOpen, hostsSearch, hostsEmpty, hostsAll
    case hostsIndependent, hostsAccounts, hostsOfWhich, relaySampleTitle
    case hostsStatusActive, hostsStatusIdle, hostsStatusOffline
    case hostsStatusThrottled, hostsStatusBanned, hostsRelayNote
    case authResolving, authNotResolved

    // Rules
    case settingsRules, rulesEmpty, ruleAdd, ruleDelete, ruleForever, ruleUntil
    case ruleKeyword, ruleRegex, ruleDomain, ruleHandle, ruleSelfHosted, ruleSelfHostedHint
    case ruleInvalidRegex, rulePlaceholderKeyword, rulePlaceholderRegex
    case rulePlaceholderDomain, rulePlaceholderHandle, rulesActive

    // Accounts and repository
    case accountAdd, accountSwitch, accountsTitle
    case repoTitle, repoExport, repoExportHint, repoShare, repoContents
    case settingsDID, settingsServer
    case settingsAbout, settingsVersion, settingsProtocol

    // Moderation
    case labelIgnore, labelWarn, labelHide
    case labelHidden, labelWarned, labelPorn, labelSexual, labelNudity, labelGraphic
    case moderationBlockedBy, moderationViaList
    case settingsModeration, moderationAdult, moderationAdultHint
    case moderationLabels, moderationLabelsHint
    case moderationShowAnyway, moderationHide, moderationCovered
    case moderationAccounts, moderationMutedCount, moderationBlockedCount
    case moderationSelfLabel, moderationByLabeler, moderationByDevice, moderationByWord

    // Discovering
    case discoverFeeds, discoverPeople, discoverKeep, discoverRemove, discoverKept
    case quotesTitle, quotesEmpty

    // Spoken only — these never appear on screen
    case a11yQuoteOf, a11yPostImage, a11ySettings, a11yMore, a11yNewList
    case a11yDeleteWord, a11yServiceSettings, a11yCloseSheet

    // Making an account
    case deleteAccount, deleteAccountHint, deleteAccountRequest, deleteAccountSent
    case deleteAccountCode, deleteAccountConfirm, deleteAccountQuestion, deleteAccountFinal

    // Message rules and report routing
    case messagesWho, messagesFromAll, messagesFromFollowing, messagesFromNobody
    case convoMute, convoUnmute, convoLeave, convoLeaveQuestion, convoMuted
    case reportMessage, reportTo, reportToDefault

    // One's own space
    case replyEverybody, replyNobody, replyMentioned, replyFollowed, replyFollowers, replyList
    case replyWho, replyNobodyNotice, replyLimitedNotice, replyDisabled
    case quotesAllowed, quotesDisabled, quoteDetach
    case hidePost, unhidePost, hiddenPostNotice, hideReply, unhideReply, replyHidden

    // Muted words and lists
    case mutedWordsTitle, mutedWordsHint, mutedWordsEmpty, mutedWordAdd, mutedWordPlaceholder
    case mutedWordText, mutedWordTag, mutedWordEveryone, mutedWordStrangers
    case mutedWordReason, mutedWordDelete, mutedWordExpiry, mutedWordForever
    case mutedWordDay, mutedWordWeek, mutedWordMonth, mutedWordsOpen, mutedWordRemaining
    case listsTitle, listsHint, listsEmpty, listsMine, listsSubscribed, listsOpen
    case listMute, listUnmute, listBlock, listUnblock, listMembers, listAddTo
    case listCreate, listNamePlaceholder, listAdded, listRemoved, listNone

    // Labelers
    case labelersTitle, labelersHint, labelersEmpty, labelersSearch, labelersSearchHint
    case labelersSubscribe, labelersUnsubscribe, labelersValues, labelersApplied
    case labelersAppliedHint, labelersIsLabeler, labelersOpen

    // Relay
    case radarPosts, radarLikes, radarReposts, radarFollows, radarAll
    case relayTitle, relayHint, relayThroughput, relayPerSecond
    case relayLatency, relayLatencyHint, relaySeen, relayComposition
    case relayServers, relaySample, relaySelfHosted, relayLatest, relayWaiting
    case relayConnecting, relayLive, relayOffline, relayPulse, relayPulseHint

    // Time
    case timeNow, timeMinute, timeHour, timeDay

    // Errors
    case errorInvalidURL, errorTransport, errorServer, errorDecoding, errorUnauthenticated
    case errorRateLimited, errorChatNotPermitted, errorSessionExpired, errorOffline
    case offlineBanner
}

enum L10n {
    /// Written only from the main thread (settings screen).
    static var language: AppLanguage = .en

    static func t(_ key: LKey) -> String {
        let table = language.resolved == .de ? german : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    static func t(_ key: LKey, _ arguments: CVarArg...) -> String {
        String(format: t(key), arguments: arguments)
    }

    /// Keys with no entry in one of the tables. Comparing rendered text against the
    /// key name would report a false gap whenever the two happen to match.
    static func keysWithoutText() -> [String] {
        LKey.allCases.flatMap { key -> [String] in
            var gaps: [String] = []
            if german[key] == nil { gaps.append("de/\(key.rawValue)") }
            if english[key] == nil { gaps.append("en/\(key.rawValue)") }
            return gaps
        }
    }

    /// Entries that read as the other language. A missing translation is caught
    /// by `keysWithoutText()`; text that was never translated at all — German
    /// left standing in the English table — looks complete and needs its own
    /// check. The word lists only have to catch a block of untranslated text,
    /// not judge prose.
    static func keysInTheWrongLanguage() -> [String] {
        let germanWords: Set<String> = ["der", "die", "das", "und", "nicht", "noch", "für",
                                        "mit", "dem", "den", "eine", "einen", "kein", "keine",
                                        "wem", "dich", "dein", "deine", "schreiben", "werden",
                                        "wird", "ist", "sind", "auf", "aus", "kann"]
        let englishWords: Set<String> = ["the", "you", "your", "and", "with", "not", "this",
                                         "that", "from", "every", "cannot", "here"]

        return LKey.allCases.flatMap { key -> [String] in
            var wrong: [String] = []
            if let text = english[key],
               text.contains(where: { "äöüß".contains($0) }) || !words(in: text).isDisjoint(with: germanWords) {
                wrong.append("en/\(key.rawValue)")
            }
            if let text = german[key], !words(in: text).isDisjoint(with: englishWords) {
                wrong.append("de/\(key.rawValue)")
            }
            return wrong
        }
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init))
    }

    private static let german: [LKey: String] = [
        .authIdentifier: "Handle oder DID",
        .authPassword: "App-Passwort",
        .authConnect: "Verbinden",

        .tabFeed: "Feed",
        .tabSearch: "Suche",
        .tabNotifications: "Meldungen",
        .tabProfile: "Profil",
        .titleThread: "Thread",
        .titleSettings: "Einstellungen",

        .feedEmpty: "Hier ist noch nichts.\nFolge ein paar Konten, dann füllt sich dein Feed.",
        .feedFollowing: "Folge ich",
        .feedRepostedBy: "%@ repostete",
        .replyingTo: "Antwort an @%@",
        .retry: "erneut versuchen",
        .loadingImages: "Bild",

        .composePlaceholder: "Was gibt's?",
        .composeReplyPlaceholder: "Antworten …",
        .composeReplyTo: "Antwort an @%@",
        .composeAddImages: "Bilder hinzufügen",
        .composeRemoveImage: "Bild entfernen",
        .composeAddAlt: "+ALT",
        .composeImageFailed: "Bild konnte nicht gelesen werden.",
        .composeAltTitle: "Bildbeschreibung",
        .composeAltPlaceholder: "Was ist auf dem Bild zu sehen?",
        .composeAltHint: "Beschreibungen machen Beiträge für Menschen lesbar, die das Bild nicht sehen können.",
        .composeAddVideo: "Video hinzufügen",
        .composeVideoFailed: "Video konnte nicht gelesen werden.",
        .composeVideoTooLarge: "Das Video ist zu groß.",
        .composeVideoProgress: "Wird verarbeitet … %d %%",
        .cancel: "Abbrechen",
        .send: "Senden",

        .statFollowers: "Follower",
        .statFollowing: "Folgt",
        .statPosts: "Beiträge",
        .profileEmpty: "Noch keine Posts.",
        .actorListEmpty: "Niemand hier.",
        .sectionReplies: "Antworten",
        .sectionMedia: "Medien",
        .follow: "Folgen",
        .unfollow: "Folge ich",
        .unfollowAction: "Nicht mehr folgen",
        .verified: "Verifiziert",
        .trustedVerifier: "Verifiziert andere Konten",

        .moderationReport: "Melden",
        .moderationMute: "Stummschalten",
        .moderationUnmute: "Stummschaltung aufheben",
        .moderationBlock: "Blockieren",
        .moderationUnblock: "Blockierung aufheben",
        .moderationDelete: "Beitrag löschen",
        .moderationDeleteQuestion: "Diesen Beitrag löschen?",
        .moderationBlocked: "Blockiert",
        .moderationMuted: "Stummgeschaltet",
        .reportPost: "Diesen Beitrag melden",
        .reportAccount: "Dieses Konto melden",
        .reportNote: "Was sollte die Moderation wissen? (optional)",
        .reportSend: "Meldung senden",
        .reportSent: "Danke — die Meldung ist raus.",
        .reportSpam: "Spam",
        .reportViolation: "Regelverstoß",
        .reportMisleading: "Irreführend",
        .reportSexual: "Unerwünscht sexuell",
        .reportRude: "Beleidigend",
        .reportOther: "Etwas anderes",
        .editProfile: "Profil bearbeiten",
        .editName: "Anzeigename",
        .editAbout: "Über dich",
        .editAvatar: "Profilbild ändern",
        .editBanner: "Banner ändern",
        .editTooLong: "Text ist zu lang.",
        .save: "Speichern",
        .signOut: "Abmelden",
        .signOutQuestion: "Abmelden?",

        .notificationsEmpty: "Keine Meldungen.",
        .verbLike: "hat geliked",
        .verbRepost: "hat repostet",
        .verbFollow: "folgt dir",
        .verbMention: "hat dich erwähnt",
        .verbReply: "hat geantwortet",
        .verbQuote: "hat zitiert",
        .verbLikeViaRepost: "hat über einen Repost geliked",
        .verbRepostViaRepost: "hat über einen Repost repostet",
        .verbStarterpackJoined: "ist über dein Starter Pack beigetreten",
        .verbVerified: "hat dich verifiziert",
        .verbUnverified: "hat die Verifizierung zurückgenommen",
        .verbSubscribedPost: "hat etwas gepostet",
        .verbContactMatch: "ist auch hier",
        .verbUnknown: "hat etwas getan, das Relays nicht kennt",
        .notifyMore: "und %@ weitere",
        .verbStarterpackNamed: "ist über %@ beigetreten",
        .notifyKinds: "Was dich erreicht",
        .notifyKindsHint: "Diese Einstellungen liegen auf dem Konto, nicht auf diesem Gerät. Sie gelten in jedem Bluesky-Client, den du benutzt.",
        .notifyAudience: "Von wem",
        .notifyAudienceAll: "Von allen",
        .notifyAudienceFollows: "Nur von Gefolgten",
        .notifyAudienceMixed: "Gemischt",
        .notifyOff: "Aus",
        .notifyListOnly: "In der Liste",
        .notifyAlert: "Melden",
        .notifyGroupPosts: "Deine Beiträge",
        .notifyGroupAccount: "Dein Konto",
        .notifyGroupSubscriptions: "Abonnements",
        .notifyKindReply: "Antworten",
        .notifyKindMention: "Erwähnungen",
        .notifyKindQuote: "Zitate",
        .notifyKindLike: "Likes",
        .notifyKindRepost: "Reposts",
        .notifyKindLikeViaRepost: "Likes über einen Repost",
        .notifyKindRepostViaRepost: "Reposts über einen Repost",
        .notifyKindFollow: "Neue Follower",
        .notifyKindVerified: "Verifizierungen",
        .notifyKindUnverified: "Zurückgenommene Verifizierungen",
        .notifyKindStarterpack: "Beitritte über dein Starter Pack",
        .notifyKindSubscribed: "Beiträge abonnierter Konten",
        .notifySubscriptionsHint: "Abonnements selbst lassen sich in Relays noch nicht verwalten.",

        .searchPlaceholder: "Handle oder Name",
        .searchEmpty: "Nichts gefunden.",
        .searchHint: "Accounts und Beiträge im Netzwerk finden.",
        .searchPeople: "Personen",
        .searchPosts: "Beiträge",
        .hashtagEmpty: "Noch nichts unter %@.",

        .settingsAppearance: "Darstellung",
        .settingsFeed: "Feed",
        .settingsBehavior: "Verhalten",
        .settingsCompact: "Kompakte Ansicht",
        .settingsAltBadge: "Alt-Markierung auf Bildern",
        .settingsCounts: "Zähler anzeigen",
        .settingsHideReposts: "Reposts ausblenden",
        .settingsHideReplies: "Antworten ausblenden",
        .settingsAutoRefresh: "Beim Öffnen aktualisieren",
        .settingsOpenInApp: "Links in der App öffnen",
        .settingsHaptics: "Haptisches Feedback",
        .settingsShowOrigin: "Server am Beitrag zeigen",
        .settingsDynamicType: "Systemschriftgröße folgen",
        .settingsNotifications: "Benachrichtigungen",
        .notifyEnabled: "Benachrichtigungen",
        .notifyLikes: "Likes",
        .notifyReposts: "Reposts",
        .notifyFollows: "Neue Follower",
        .notifyReplies: "Antworten und Erwähnungen",
        .notifyDenied: "In den Systemeinstellungen deaktiviert.",
        .notifyHint: "Relays sieht im Hintergrund nach. Wie oft das geschieht, entscheidet iOS.",
        .settingsTheme: "Hintergrund",
        .themeLight: "Hell",
        .themeDim: "Gedimmt",
        .themeDark: "Dunkel",
        .themeBlue: "Blau",
        .settingsTypeface: "Schrift",
        .settingsSystemFace: "System",
        .actionReply: "Antworten",
        .actionRepost: "Reposten",
        .actionLike: "Liken",
        .actionUnlike: "Like zurücknehmen",
        .actionUndoRepost: "Repost zurücknehmen",
        .actionQuote: "Zitieren",

        .inspectorTitle: "Record",
        .inspectorAuthor: "Konto",
        .inspectorDID: "DID",
        .inspectorPDS: "PDS",
        .inspectorURI: "AT-URI",
        .inspectorCID: "CID",
        .inspectorCreated: "Erstellt",
        .inspectorIndexed: "Indexiert",
        .inspectorFacets: "Facets",
        .inspectorRecord: "Rohdaten",
        .close: "Schließen",
        .imagePrevious: "Vorheriges Bild",
        .imageNext: "Nächstes Bild",
        .imageCount: "Bild %@ von %@",
        .refresh: "Aktualisieren",
        .embedFeed: "Feed",
        .embedList: "Liste",
        .embedStarterPack: "Starter Pack",
        .embedNotFound: "Der zitierte Beitrag existiert nicht mehr.",
        .embedBlocked: "Zitat eines blockierten Kontos.",
        .embedDetached: "Der Autor hat dieses Zitat gelöst.",
        .embedJoined: "%@ beigetreten",
        .embedLikes: "%@ Likes",
        .likesTitle: "Geliked von",
        .repostsTitle: "Repostet von",
        .postListEmpty: "Noch niemand.",
        .seeLikes: "Wer hat geliked",
        .seeReposts: "Wer hat repostet",
        .hostsTitle: "Server-Register",
        .hostsHint: "Jeder Server, von dem dieses Relay liest. Nicht die Stichprobe aus der Firehose, sondern das Verzeichnis selbst.",
        .hostsOpen: "Das Register ansehen",
        .hostsSearch: "Server suchen",
        .hostsEmpty: "Kein Server passt dazu.",
        .hostsAll: "Alle",
        .hostsIndependent: "unabhängig",
        .hostsAccounts: "Konten",
        .hostsOfWhich: "%@ davon auf unabhängigen Servern",
        .relaySampleTitle: "Server (Stichprobe)",
        .hostsStatusActive: "aktiv",
        .hostsStatusIdle: "im Leerlauf",
        .hostsStatusOffline: "offline",
        .hostsStatusThrottled: "gedrosselt",
        .hostsStatusBanned: "gesperrt",
        .hostsRelayNote: "Angaben von %@. Ein Relay spricht nur für sich, und sein Bild hinkt hinterher.",
        .authResolving: "Server wird gesucht …",
        .authNotResolved: "Dazu findet das Netz nichts.",
        .copied: "kopiert",
        .video: "Video",
        .videoUnavailable: "Video nicht verfügbar.",
        .inspect: "Record ansehen",
        .hostedOn: "gehostet auf %@",

        .tabMessages: "Nachrichten",
        .messagesEmpty: "Noch keine Unterhaltungen.",
        .messagePlaceholder: "Nachricht schreiben",
        .newMessage: "Neue Nachricht",
        .newMessageSearch: "Wem schreiben?",
        .newMessageHint: "Suche jemanden, dem du schreiben möchtest.",

        .settingsRules: "Feed-Regeln",
        .rulesEmpty: "Noch keine Regeln.",
        .ruleAdd: "Hinzufügen",
        .ruleDelete: "Regel löschen",
        .ruleForever: "dauerhaft",
        .ruleUntil: "bis %@",
        .ruleKeyword: "Stichwort",
        .ruleRegex: "Muster",
        .ruleDomain: "Domain",
        .ruleHandle: "Handle",
        .ruleSelfHosted: "Nur selbst gehostete",
        .ruleSelfHostedHint: "Blendet alle Konten aus, die auf Blueskys eigenen Servern liegen.",
        .ruleInvalidRegex: "Ungültiger regulärer Ausdruck.",
        .rulePlaceholderKeyword: "Wort, das ausgeblendet wird",
        .rulePlaceholderRegex: "z. B. ^GM |spoiler",
        .rulePlaceholderDomain: "z. B. example.com",
        .rulePlaceholderHandle: "Teil eines Handles",
        .rulesActive: "%d aktiv",

        .accountAdd: "Konto hinzufügen",
        .accountSwitch: "Wechseln",
        .accountsTitle: "Konten",
        .repoTitle: "Repository",
        .repoExport: "Repository sichern",
        .repoExportHint: "Lädt dein vollständiges Repository als CAR-Datei: jeder Post, jeder Like, jeder Follow — signiert und offline lesbar.",
        .repoShare: "Datei sichern",
        .repoContents: "Inhalt",
        .settingsLanguage: "Sprache",
        .settingsLanguageSystem: "System",
        .settingsTextSize: "Textgröße",
        .settingsTextSizeSmall: "Klein",
        .settingsTextSizeMedium: "Mittel",
        .settingsTextSizeLarge: "Groß",
        .settingsSlimFonts: "Schlanke Schrift",
        .settingsShowImages: "Bilder laden",
        .settingsAbsoluteTime: "Absolute Zeitangaben",
        .settingsDID: "DID",
        .settingsServer: "PDS",
        .settingsAbout: "Über",
        .settingsVersion: "Version",
        .settingsProtocol: "Protokoll",

        .timeNow: "jetzt",
        .timeMinute: "m",
        .timeHour: "h",
        .timeDay: "t",

        .labelIgnore: "Zeigen",
        .labelWarn: "Warnen",
        .labelHide: "Ausblenden",
        .labelHidden: "Ausgeblendet",
        .labelWarned: "Mit Warnung versehen",
        .labelPorn: "Pornografie",
        .labelSexual: "Sexuell anzüglich",
        .labelNudity: "Nacktheit",
        .labelGraphic: "Drastische Darstellung",
        .moderationBlockedBy: "Dieses Konto blockiert dich",
        .moderationViaList: "Über die Liste %@",
        .settingsModeration: "Moderation",
        .moderationAdult: "Sensible Inhalte",
        .moderationAdultHint: "Aus lässt jeden als sensibel markierten Beitrag verschwinden, unabhängig von den Einstellungen darunter.",
        .moderationLabels: "Labels",
        .moderationLabelsHint: "Gilt für Labels, die Autoren selbst setzen, und für die Dienste, die dein Server anwendet.",
        .moderationShowAnyway: "Trotzdem zeigen",
        .moderationHide: "Wieder verdecken",
        .moderationCovered: "Verdeckt",
        .moderationAccounts: "Konten",
        .moderationMutedCount: "%d stummgeschaltet",
        .moderationBlockedCount: "%d blockiert",
        .moderationSelfLabel: "vom Autor",
        .moderationByLabeler: "von einem Moderationsdienst",
        .moderationByDevice: "von deiner Regel",
        .moderationByWord: "von deinem stummen Wort",
        .labelersTitle: "Moderationsdienste",
        .labelersHint: "Jeder Dienst vergibt eigene Labels und sagt selbst, was sie bedeuten. Du entscheidest pro Label, was damit geschieht.",
        .labelersEmpty: "Noch kein Dienst abonniert.",
        .labelersSearch: "Dienst suchen",
        .labelersSearchHint: "Suche nach einem Konto, das einen Moderationsdienst betreibt.",
        .labelersSubscribe: "Abonnieren",
        .labelersUnsubscribe: "Nicht mehr abonnieren",
        .labelersValues: "%d Labels",
        .labelersApplied: "Vom Server angewandt",
        .labelersAppliedHint: "Diese Dienste wendet dein Server unabhängig von deiner Auswahl an.",
        .labelersIsLabeler: "Moderationsdienst",
        .labelersOpen: "Dienste verwalten",
        .mutedWordsTitle: "Stumme Wörter",
        .mutedWordsHint: "Beiträge mit diesen Wörtern erscheinen nicht. Gespeichert bei deinem Konto, also überall gleich.",
        .mutedWordsEmpty: "Noch keine Wörter.",
        .mutedWordAdd: "Hinzufügen",
        .mutedWordPlaceholder: "Wort oder Wortfolge",
        .mutedWordText: "Text",
        .mutedWordTag: "Hashtag",
        .mutedWordEveryone: "Alle",
        .mutedWordStrangers: "Außer wem ich folge",
        .mutedWordReason: "Stummes Wort: %@",
        .mutedWordDelete: "Wort entfernen",
        .mutedWordExpiry: "Dauer",
        .mutedWordForever: "Dauerhaft",
        .mutedWordDay: "1 Tag",
        .mutedWordWeek: "7 Tage",
        .mutedWordMonth: "30 Tage",
        .mutedWordsOpen: "Stumme Wörter",
        .mutedWordRemaining: "noch %@",
        .listsTitle: "Listen",
        .listsHint: "Eine Liste behandelt viele Konten auf einmal — stummschalten oder blockieren.",
        .listsEmpty: "Noch keine Listen.",
        .listsMine: "Eigene Listen",
        .listsSubscribed: "Abonniert",
        .listsOpen: "Listen",
        .listMute: "Stummschalten",
        .listUnmute: "Stummschaltung aufheben",
        .listBlock: "Blockieren",
        .listUnblock: "Blockierung aufheben",
        .listMembers: "%d Konten",
        .listAddTo: "Zu Liste hinzufügen",
        .listCreate: "Liste anlegen",
        .listNamePlaceholder: "Name der Liste",
        .listAdded: "Hinzugefügt",
        .listRemoved: "Entfernt",
        .listNone: "Keine eigene Liste vorhanden.",
        .replyEverybody: "Alle",
        .replyNobody: "Niemand",
        .replyMentioned: "Erwähnte",
        .replyFollowed: "Wem ich folge",
        .replyFollowers: "Meine Follower",
        .replyList: "Eine Liste",
        .replyWho: "Wer darf antworten",
        .replyNobodyNotice: "Antworten sind ausgeschaltet",
        .replyLimitedNotice: "Antworten nur: %@",
        .replyDisabled: "Du kannst auf diesen Beitrag nicht antworten.",
        .quotesAllowed: "Zitate erlauben",
        .quotesDisabled: "Zitate ausgeschaltet",
        .quoteDetach: "Zitat ablösen",
        .hidePost: "Beitrag für mich ausblenden",
        .unhidePost: "Wieder einblenden",
        .hiddenPostNotice: "Von dir ausgeblendet",
        .hideReply: "Antwort ausblenden",
        .unhideReply: "Antwort wieder zeigen",
        .replyHidden: "Vom Autor ausgeblendet",
        .messagesWho: "Wer darf mir schreiben",
        .messagesFromAll: "Alle",
        .messagesFromFollowing: "Wem ich folge",
        .messagesFromNobody: "Niemand",
        .convoMute: "Unterhaltung stummschalten",
        .convoUnmute: "Stummschaltung aufheben",
        .convoLeave: "Unterhaltung verlassen",
        .convoLeaveQuestion: "Diese Unterhaltung verlassen? Beim Gegenüber bleibt sie bestehen.",
        .convoMuted: "Stumm",
        .reportMessage: "Nachricht melden",
        .reportTo: "Melden an",
        .reportToDefault: "Dienst meines Servers",
        .deleteAccount: "Konto löschen",
        .deleteAccountHint: "Alles, was dein Konto hält, wird gelöscht: Beiträge, Likes, Follows, Nachrichten. Das lässt sich nicht rückgängig machen.",
        .deleteAccountRequest: "Code per E-Mail anfordern",
        .deleteAccountSent: "Wir haben dir einen Code geschickt.",
        .deleteAccountCode: "Code aus der E-Mail",
        .deleteAccountConfirm: "Konto endgültig löschen",
        .deleteAccountQuestion: "Konto endgültig löschen?",
        .deleteAccountFinal: "Es gibt keinen Weg zurück.",
        .a11yQuoteOf: "zitiert %@",
        .a11yPostImage: "Bild im Beitrag",
        .a11ySettings: "Einstellungen",
        .a11yMore: "Weitere Aktionen",
        .a11yNewList: "Neue Liste anlegen",
        .a11yDeleteWord: "Wort entfernen",
        .a11yServiceSettings: "Einstellungen dieses Dienstes",
        .a11yCloseSheet: "Schließen",
        .discoverFeeds: "Feeds",
        .discoverPeople: "Konten",
        .discoverKeep: "Behalten",
        .discoverRemove: "Entfernen",
        .discoverKept: "%@ behalten es",
        .quotesTitle: "Zitate",
        .quotesEmpty: "Noch keine Zitate.",
        .radarPosts: "Beiträge",
        .radarLikes: "Likes",
        .radarReposts: "Reposts",
        .radarFollows: "Follows",
        .radarAll: "Alles",
        .relayTitle: "Relay",
        .relayHint: "Jedes Record im Netz, in dem Moment, in dem es geschrieben wird. Öffentlich, ohne Anmeldung.",
        .relayThroughput: "Durchsatz",
        .relayPerSecond: "pro Sekunde",
        .relayLatency: "Laufzeit",
        .relayLatencyHint: "Vom Zeitstempel des Autors bis hierher. Median.",
        .relaySeen: "Gesehen",
        .relayComposition: "Zusammensetzung",
        .relayServers: "Server",
        .relaySample: "Stichprobe aus %d aufgelösten Konten",
        .relaySelfHosted: "selbst gehostet",
        .relayLatest: "Zuletzt",
        .relayWaiting: "Warte auf den Datenstrom …",
        .relayConnecting: "Verbinde",
        .relayLive: "Live",
        .relayOffline: "Getrennt",
        .relayPulse: "Puls in der Kopfzeile",
        .relayPulseHint: "Die Linie unter dem Titel zeigt den Durchsatz des Netzes.",
        .errorInvalidURL: "Ungültige Server-Adresse.",
        .errorTransport: "Keine Verbindung zum Server.",
        .errorServer: "Serverfehler (%d).",
        .errorDecoding: "Antwort konnte nicht gelesen werden.",
        .errorUnauthenticated: "Nicht angemeldet.",
        .errorRateLimited: "Zu viele Anfragen — kurz warten.",
        .errorOffline: "Keine Verbindung.",
        .offlineBanner: "Offline — die App zeigt, was sie zuletzt geladen hat.",
        .errorSessionExpired: "Deine Anmeldung gilt nicht mehr. Das App-Passwort wurde zurückgezogen oder ist abgelaufen — bitte melde dich neu an.",
        .errorChatNotPermitted: "Dieses App-Passwort erlaubt keine Direktnachrichten. Lege in den Einstellungen deines Kontos ein App-Passwort mit Nachrichten-Zugriff an und melde dich damit neu an."
    ]

    private static let english: [LKey: String] = [
        .authIdentifier: "Handle or DID",
        .authPassword: "App password",
        .authConnect: "Connect",

        .tabFeed: "Feed",
        .tabSearch: "Search",
        .tabNotifications: "Alerts",
        .tabProfile: "Profile",
        .titleThread: "Thread",
        .titleSettings: "Settings",

        .feedEmpty: "Nothing here yet.\nFollow a few accounts and your feed fills up.",
        .feedFollowing: "Following",
        .feedRepostedBy: "%@ reposted",
        .replyingTo: "Reply to @%@",
        .retry: "try again",
        .loadingImages: "Image",

        .composePlaceholder: "What's up?",
        .composeReplyPlaceholder: "Reply …",
        .composeReplyTo: "Replying to @%@",
        .composeAddImages: "Add images",
        .composeRemoveImage: "Remove image",
        .composeAddAlt: "+ALT",
        .composeImageFailed: "That image could not be read.",
        .composeAltTitle: "Image description",
        .composeAltPlaceholder: "What is in the picture?",
        .composeAltHint: "Descriptions make a post readable for people who cannot see the image.",
        .composeAddVideo: "Add video",
        .composeVideoFailed: "That video could not be read.",
        .composeVideoTooLarge: "That video is too large.",
        .composeVideoProgress: "Processing … %d%%",
        .cancel: "Cancel",
        .send: "Send",

        .statFollowers: "Followers",
        .statFollowing: "Following",
        .statPosts: "Posts",
        .profileEmpty: "No posts yet.",
        .actorListEmpty: "Nobody here.",
        .sectionReplies: "Replies",
        .sectionMedia: "Media",
        .follow: "Follow",
        .unfollow: "Following",
        .unfollowAction: "Unfollow",
        .verified: "Verified",
        .trustedVerifier: "Verifies other accounts",

        .moderationReport: "Report",
        .moderationMute: "Mute",
        .moderationUnmute: "Unmute",
        .moderationBlock: "Block",
        .moderationUnblock: "Unblock",
        .moderationDelete: "Delete post",
        .moderationDeleteQuestion: "Delete this post?",
        .moderationBlocked: "Blocked",
        .moderationMuted: "Muted",
        .reportPost: "Report this post",
        .reportAccount: "Report this account",
        .reportNote: "Anything moderation should know? (optional)",
        .reportSend: "Send report",
        .reportSent: "Thanks — the report is on its way.",
        .reportSpam: "Spam",
        .reportViolation: "Rule violation",
        .reportMisleading: "Misleading",
        .reportSexual: "Unwanted sexual content",
        .reportRude: "Abusive",
        .reportOther: "Something else",
        .editProfile: "Edit profile",
        .editName: "Display name",
        .editAbout: "About",
        .editAvatar: "Change picture",
        .editBanner: "Change banner",
        .editTooLong: "That text is too long.",
        .save: "Save",
        .signOut: "Sign out",
        .signOutQuestion: "Sign out?",

        .notificationsEmpty: "No alerts.",
        .verbLike: "liked",
        .verbRepost: "reposted",
        .verbFollow: "followed you",
        .verbMention: "mentioned you",
        .verbReply: "replied",
        .verbQuote: "quoted",
        .verbLikeViaRepost: "liked, through a repost",
        .verbRepostViaRepost: "reposted, through a repost",
        .verbStarterpackJoined: "joined through your starter pack",
        .verbVerified: "verified you",
        .verbUnverified: "withdrew a verification",
        .verbSubscribedPost: "posted",
        .verbContactMatch: "is here too",
        .verbUnknown: "did something Relays does not know about",
        .notifyMore: "and %@ more",
        .verbStarterpackNamed: "joined through %@",
        .notifyKinds: "What reaches you",
        .notifyKindsHint: "These settings live on the account, not on this device. They apply in every Bluesky client you use.",
        .notifyAudience: "From whom",
        .notifyAudienceAll: "Everyone",
        .notifyAudienceFollows: "People I follow",
        .notifyAudienceMixed: "Mixed",
        .notifyOff: "Off",
        .notifyListOnly: "In the list",
        .notifyAlert: "Alert me",
        .notifyGroupPosts: "Your posts",
        .notifyGroupAccount: "Your account",
        .notifyGroupSubscriptions: "Subscriptions",
        .notifyKindReply: "Replies",
        .notifyKindMention: "Mentions",
        .notifyKindQuote: "Quotes",
        .notifyKindLike: "Likes",
        .notifyKindRepost: "Reposts",
        .notifyKindLikeViaRepost: "Likes through a repost",
        .notifyKindRepostViaRepost: "Reposts through a repost",
        .notifyKindFollow: "New followers",
        .notifyKindVerified: "Verifications",
        .notifyKindUnverified: "Withdrawn verifications",
        .notifyKindStarterpack: "Joins through your starter pack",
        .notifyKindSubscribed: "Posts from accounts you subscribe to",
        .notifySubscriptionsHint: "Subscriptions themselves cannot be managed in Relays yet.",

        .searchPlaceholder: "Handle or name",
        .searchEmpty: "Nothing found.",
        .searchHint: "Find accounts and posts on the network.",
        .searchPeople: "People",
        .searchPosts: "Posts",
        .hashtagEmpty: "Nothing under %@ yet.",

        .settingsAppearance: "Appearance",
        .settingsFeed: "Feed",
        .settingsBehavior: "Behavior",
        .settingsCompact: "Compact layout",
        .settingsAltBadge: "Alt badge on images",
        .settingsCounts: "Show counts",
        .settingsHideReposts: "Hide reposts",
        .settingsHideReplies: "Hide replies",
        .settingsAutoRefresh: "Refresh on open",
        .settingsOpenInApp: "Open links in app",
        .settingsHaptics: "Haptic feedback",
        .settingsShowOrigin: "Show host on posts",
        .settingsDynamicType: "Follow system text size",
        .settingsNotifications: "Notifications",
        .notifyEnabled: "Notifications",
        .notifyLikes: "Likes",
        .notifyReposts: "Reposts",
        .notifyFollows: "New followers",
        .notifyReplies: "Replies and mentions",
        .notifyDenied: "Turned off in System Settings.",
        .notifyHint: "Relays checks in the background. How often that happens is up to iOS.",
        .settingsTheme: "Ground",
        .themeLight: "Light",
        .themeDim: "Dim",
        .themeDark: "Dark",
        .themeBlue: "Blue",
        .settingsTypeface: "Typeface",
        .settingsSystemFace: "System",
        .actionReply: "Reply",
        .actionRepost: "Repost",
        .actionLike: "Like",
        .actionUnlike: "Undo like",
        .actionUndoRepost: "Undo repost",
        .actionQuote: "Quote",

        .inspectorTitle: "Record",
        .inspectorAuthor: "Account",
        .inspectorDID: "DID",
        .inspectorPDS: "PDS",
        .inspectorURI: "AT URI",
        .inspectorCID: "CID",
        .inspectorCreated: "Created",
        .inspectorIndexed: "Indexed",
        .inspectorFacets: "Facets",
        .inspectorRecord: "Raw record",
        .close: "Close",
        .imagePrevious: "Previous picture",
        .imageNext: "Next picture",
        .imageCount: "Picture %@ of %@",
        .refresh: "Refresh",
        .embedFeed: "Feed",
        .embedList: "List",
        .embedStarterPack: "Starter pack",
        .embedNotFound: "The quoted post no longer exists.",
        .embedBlocked: "A quote of an account you blocked.",
        .embedDetached: "The author removed this quote.",
        .embedJoined: "%@ joined",
        .embedLikes: "%@ likes",
        .likesTitle: "Liked by",
        .repostsTitle: "Reposted by",
        .postListEmpty: "Nobody yet.",
        .seeLikes: "Who liked this",
        .seeReposts: "Who reposted this",
        .hostsTitle: "Server register",
        .hostsHint: "Every server this relay reads from. Not the firehose sample — the register itself.",
        .hostsOpen: "Open the register",
        .hostsSearch: "Search servers",
        .hostsEmpty: "No server matches.",
        .hostsAll: "All",
        .hostsIndependent: "independent",
        .hostsAccounts: "accounts",
        .hostsOfWhich: "%@ of them on independent servers",
        .relaySampleTitle: "Servers (sample)",
        .hostsStatusActive: "active",
        .hostsStatusIdle: "idle",
        .hostsStatusOffline: "offline",
        .hostsStatusThrottled: "throttled",
        .hostsStatusBanned: "banned",
        .hostsRelayNote: "Reported by %@. A relay speaks only for itself, and its view lags.",
        .authResolving: "Looking for the server …",
        .authNotResolved: "The network knows nothing by that name.",
        .copied: "copied",
        .video: "Video",
        .videoUnavailable: "Video unavailable.",
        .inspect: "View record",
        .hostedOn: "hosted on %@",

        .tabMessages: "Messages",
        .messagesEmpty: "No conversations yet.",
        .messagePlaceholder: "Write a message",
        .newMessage: "New message",
        .newMessageSearch: "Who to?",
        .newMessageHint: "Search for someone to write to.",

        .settingsRules: "Feed rules",
        .rulesEmpty: "No rules yet.",
        .ruleAdd: "Add",
        .ruleDelete: "Delete rule",
        .ruleForever: "forever",
        .ruleUntil: "until %@",
        .ruleKeyword: "Keyword",
        .ruleRegex: "Pattern",
        .ruleDomain: "Domain",
        .ruleHandle: "Handle",
        .ruleSelfHosted: "Self-hosted only",
        .ruleSelfHostedHint: "Hides every account that lives on Bluesky's own servers.",
        .ruleInvalidRegex: "Not a valid regular expression.",
        .rulePlaceholderKeyword: "Word to hide",
        .rulePlaceholderRegex: "e.g. ^GM |spoiler",
        .rulePlaceholderDomain: "e.g. example.com",
        .rulePlaceholderHandle: "Part of a handle",
        .rulesActive: "%d active",

        .accountAdd: "Add account",
        .accountSwitch: "Switch",
        .accountsTitle: "Accounts",
        .repoTitle: "Repository",
        .repoExport: "Export repository",
        .repoExportHint: "Downloads your complete repository as a CAR file: every post, like and follow — signed and readable offline.",
        .repoShare: "Save file",
        .repoContents: "Contents",
        .settingsLanguage: "Language",
        .settingsLanguageSystem: "System",
        .settingsTextSize: "Text size",
        .settingsTextSizeSmall: "Small",
        .settingsTextSizeMedium: "Medium",
        .settingsTextSizeLarge: "Large",
        .settingsSlimFonts: "Slim type",
        .settingsShowImages: "Load images",
        .settingsAbsoluteTime: "Absolute timestamps",
        .settingsDID: "DID",
        .settingsServer: "PDS",
        .settingsAbout: "About",
        .settingsVersion: "Version",
        .settingsProtocol: "Protocol",

        .timeNow: "now",
        .timeMinute: "m",
        .timeHour: "h",
        .timeDay: "d",

        .labelIgnore: "Show",
        .labelWarn: "Warn",
        .labelHide: "Hide",
        .labelHidden: "Hidden",
        .labelWarned: "Flagged",
        .labelPorn: "Pornography",
        .labelSexual: "Sexually suggestive",
        .labelNudity: "Nudity",
        .labelGraphic: "Graphic media",
        .moderationBlockedBy: "This account blocks you",
        .moderationViaList: "Via the list %@",
        .settingsModeration: "Moderation",
        .moderationAdult: "Sensitive content",
        .moderationAdultHint: "Off removes every post marked sensitive, whatever the settings below say.",
        .moderationLabels: "Labels",
        .moderationLabelsHint: "Applies to labels authors set themselves and to the services your server applies.",
        .moderationShowAnyway: "Show anyway",
        .moderationHide: "Cover again",
        .moderationCovered: "Covered",
        .moderationAccounts: "Accounts",
        .moderationMutedCount: "%d muted",
        .moderationBlockedCount: "%d blocked",
        .moderationSelfLabel: "by the author",
        .moderationByLabeler: "by a moderation service",
        .moderationByDevice: "by your rule",
        .moderationByWord: "by your muted word",
        .labelersTitle: "Moderation services",
        .labelersHint: "Each service applies its own labels and says what they mean. You decide per label what happens.",
        .labelersEmpty: "No service subscribed yet.",
        .labelersSearch: "Find a service",
        .labelersSearchHint: "Search for an account that runs a moderation service.",
        .labelersSubscribe: "Subscribe",
        .labelersUnsubscribe: "Unsubscribe",
        .labelersValues: "%d labels",
        .labelersApplied: "Applied by your server",
        .labelersAppliedHint: "Your server applies these services whatever you choose.",
        .labelersIsLabeler: "Moderation service",
        .labelersOpen: "Manage services",
        .mutedWordsTitle: "Muted words",
        .mutedWordsHint: "Posts with these words do not appear. Stored with your account, so they hold everywhere.",
        .mutedWordsEmpty: "No words yet.",
        .mutedWordAdd: "Add",
        .mutedWordPlaceholder: "Word or phrase",
        .mutedWordText: "Text",
        .mutedWordTag: "Hashtag",
        .mutedWordEveryone: "Everyone",
        .mutedWordStrangers: "Except who I follow",
        .mutedWordReason: "Muted word: %@",
        .mutedWordDelete: "Remove word",
        .mutedWordExpiry: "For",
        .mutedWordForever: "Forever",
        .mutedWordDay: "1 day",
        .mutedWordWeek: "7 days",
        .mutedWordMonth: "30 days",
        .mutedWordsOpen: "Muted words",
        .mutedWordRemaining: "%@ left",
        .listsTitle: "Lists",
        .listsHint: "A list handles many accounts at once — muted or blocked.",
        .listsEmpty: "No lists yet.",
        .listsMine: "My lists",
        .listsSubscribed: "Subscribed",
        .listsOpen: "Lists",
        .listMute: "Mute",
        .listUnmute: "Unmute",
        .listBlock: "Block",
        .listUnblock: "Unblock",
        .listMembers: "%d accounts",
        .listAddTo: "Add to list",
        .listCreate: "New list",
        .listNamePlaceholder: "List name",
        .listAdded: "Added",
        .listRemoved: "Removed",
        .listNone: "No list of your own yet.",
        .replyEverybody: "Everyone",
        .replyNobody: "Nobody",
        .replyMentioned: "Mentioned",
        .replyFollowed: "People I follow",
        .replyFollowers: "My followers",
        .replyList: "A list",
        .replyWho: "Who can reply",
        .replyNobodyNotice: "Replies are off",
        .replyLimitedNotice: "Replies limited to: %@",
        .replyDisabled: "You cannot reply to this post.",
        .quotesAllowed: "Allow quotes",
        .quotesDisabled: "Quotes are off",
        .quoteDetach: "Detach quote",
        .hidePost: "Hide post for me",
        .unhidePost: "Show again",
        .hiddenPostNotice: "Hidden by you",
        .hideReply: "Hide reply",
        .unhideReply: "Show reply again",
        .replyHidden: "Hidden by the author",
        .messagesWho: "Who can message me",
        .messagesFromAll: "Everyone",
        .messagesFromFollowing: "People I follow",
        .messagesFromNobody: "Nobody",
        .convoMute: "Mute conversation",
        .convoUnmute: "Unmute conversation",
        .convoLeave: "Leave conversation",
        .convoLeaveQuestion: "Leave this conversation? The other side keeps theirs.",
        .convoMuted: "Muted",
        .reportMessage: "Report message",
        .reportTo: "Report to",
        .reportToDefault: "My server's service",
        .deleteAccount: "Delete account",
        .deleteAccountHint: "Everything your account holds will be deleted: posts, likes, follows, messages. This cannot be undone.",
        .deleteAccountRequest: "Email me a code",
        .deleteAccountSent: "We sent you a code.",
        .deleteAccountCode: "Code from the email",
        .deleteAccountConfirm: "Delete account for good",
        .deleteAccountQuestion: "Delete this account for good?",
        .deleteAccountFinal: "There is no way back.",
        .a11yQuoteOf: "quoting %@",
        .a11yPostImage: "Image in post",
        .a11ySettings: "Settings",
        .a11yMore: "More actions",
        .a11yNewList: "Create list",
        .a11yDeleteWord: "Remove word",
        .a11yServiceSettings: "Settings for this service",
        .a11yCloseSheet: "Close",
        .discoverFeeds: "Feeds",
        .discoverPeople: "Accounts",
        .discoverKeep: "Keep",
        .discoverRemove: "Remove",
        .discoverKept: "%@ keep it",
        .quotesTitle: "Quotes",
        .quotesEmpty: "No quotes yet.",
        .radarPosts: "Posts",
        .radarLikes: "Likes",
        .radarReposts: "Reposts",
        .radarFollows: "Follows",
        .radarAll: "All",
        .relayTitle: "Relay",
        .relayHint: "Every record on the network, the moment it is written. Public, no account needed.",
        .relayThroughput: "Throughput",
        .relayPerSecond: "per second",
        .relayLatency: "Latency",
        .relayLatencyHint: "From the author's timestamp to arrival here. Median.",
        .relaySeen: "Seen",
        .relayComposition: "Composition",
        .relayServers: "Servers",
        .relaySample: "Sample of %d resolved accounts",
        .relaySelfHosted: "self-hosted",
        .relayLatest: "Latest",
        .relayWaiting: "Waiting for the stream …",
        .relayConnecting: "Connecting",
        .relayLive: "Live",
        .relayOffline: "Disconnected",
        .relayPulse: "Pulse in the header",
        .relayPulseHint: "The line under the title shows what the network is writing.",
        .errorInvalidURL: "Invalid server address.",
        .errorTransport: "Cannot reach the server.",
        .errorServer: "Server error (%d).",
        .errorDecoding: "Could not read the response.",
        .errorUnauthenticated: "Not signed in.",
        .errorRateLimited: "Too many requests — give it a moment.",
        .errorOffline: "No connection.",
        .offlineBanner: "Offline — showing what was loaded last.",
        .errorSessionExpired: "Your sign-in no longer works. The app password was revoked or has expired — please sign in again.",
        .errorChatNotPermitted: "This app password cannot use direct messages. Create one with message access in your account settings and sign in with that."
    ]
}

/// Shorthand for the views.
func L(_ key: LKey) -> String { L10n.t(key) }
func L(_ key: LKey, _ arguments: CVarArg...) -> String {
    String(format: L10n.t(key), arguments: arguments)
}
