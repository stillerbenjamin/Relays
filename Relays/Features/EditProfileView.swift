//
//  EditProfileView.swift
//  Relays
//
//  Editing one's own profile record: name, description, avatar and banner.
//

import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var about = ""
    @State private var avatar: ImageAttachment?
    @State private var banner: ImageAttachment?
    @State private var pickedAvatar: PhotosPickerItem?
    @State private var pickedBanner: PhotosPickerItem?
    @State private var existing: ProfileRecord?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let nameLimit = 64
    private let aboutLimit = 256

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        images
                        fields

                        if let errorMessage {
                            Text(errorMessage)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.danger)
                                .padding(.horizontal, Theme.Metric.hPadding)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.never)
            }
        }
        .relaysBackground()
        .relaysColorScheme()
        .task { await load() }
        .onChange(of: pickedAvatar) { _, item in
            Task { if let item { avatar = await ImageAttachment.load(from: item) } }
        }
        .onChange(of: pickedBanner) { _, item in
            Task { if let item { banner = await ImageAttachment.load(from: item) } }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L(.cancel)) { dismiss() }
                    .font(Theme.Font.ui(15))
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                Text(L(.editProfile))
                    .font(Theme.Font.ui(17, .semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer()

                Button(action: save) {
                    if isSaving {
                        ProgressView().controlSize(.small).tint(Theme.Palette.onAccent)
                    } else {
                        Text(L(.save))
                            .font(Theme.Font.ui(15, .semibold))
                            .foregroundStyle(Theme.Palette.onAccent)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Theme.Palette.accent))
                .buttonStyle(.plain)
                .disabled(isSaving || isLoading)
            }
            .padding(.horizontal, Theme.Metric.hPadding)
            .frame(height: 56)
            Hairline()
        }
    }

    /// Banner behind, avatar overlapping — the same arrangement the profile shows,
    /// so the edit screen previews the result.
    ///
    /// The pickers' labels are not on the main actor, so everything they draw
    /// with is read here and handed in.
    @MainActor
    private var images: some View {
        let surface = Theme.Palette.surface
        let onMedia = Theme.Palette.onMedia
        let scrim = Theme.Palette.mediaScrim
        let ground = Theme.Palette.background
        let bannerURL = app.profile?.bannerURL
        let avatarURL = app.profile?.avatarURL
        let handle = app.session?.handle ?? "?"
        let bannerPreview = banner?.preview
        let avatarPreview = avatar?.preview

        return ZStack(alignment: .bottomLeading) {
            PhotosPicker(selection: $pickedBanner, matching: .images) {
                ZStack {
                    if let bannerPreview {
                        bannerPreview.resizable().scaledToFill()
                    } else if let bannerURL {
                        AsyncImage(url: bannerURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            default: surface
                            }
                        }
                    } else {
                        surface
                    }
                    Image(systemName: "camera")
                        .font(.system(size: 20))
                        .foregroundStyle(onMedia)
                        .padding(12)
                        .background(Circle().fill(scrim))
                }
                .frame(height: 124)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L(.editBanner))

            PhotosPicker(selection: $pickedAvatar, matching: .images) {
                ZStack {
                    if let avatarPreview {
                        avatarPreview.resizable().scaledToFill()
                    } else {
                        AvatarView(url: avatarURL, seed: handle, size: 76)
                    }
                    Image(systemName: "camera")
                        .font(.system(size: 15))
                        .foregroundStyle(onMedia)
                        .padding(8)
                        .background(Circle().fill(scrim))
                }
                .frame(width: 76, height: 76)
                .clipShape(Circle())
                .overlay(Circle().stroke(ground, lineWidth: 4))
            }
            .buttonStyle(.plain)
            .padding(.leading, Theme.Metric.hPadding)
            .offset(y: 38)
            .accessibilityLabel(L(.editAvatar))
        }
        .padding(.bottom, 46)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L(.editName), count: displayName.count, limit: nameLimit)
                TextField("", text: $displayName)
                    .font(Theme.Font.ui(16))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Palette.surface))
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel(L(.editAbout), count: about.count, limit: aboutLimit)
                TextField("", text: $about, axis: .vertical)
                    .font(Theme.Font.ui(16))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(4, reservesSpace: true)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Palette.surface))
            }
        }
        .padding(.horizontal, Theme.Metric.hPadding)
    }

    private func fieldLabel(_ text: String, count: Int, limit: Int) -> some View {
        HStack {
            Text(text)
                .font(Theme.Font.ui(13, .semibold))
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text("\(count)/\(limit)")
                .font(Theme.Font.mono(11))
                .foregroundStyle(count > limit ? Theme.Palette.danger : Theme.Palette.textTertiary)
        }
    }

    private func load() async {
        guard let did = app.session?.did else { return }
        existing = try? await app.client.profileRecord(did: did)
        displayName = existing?.displayName ?? app.profile?.displayName ?? ""
        about = existing?.description ?? app.profile?.description ?? ""
        isLoading = false
    }

    private func save() {
        guard !isSaving else { return }
        guard displayName.count <= nameLimit, about.count <= aboutLimit else {
            errorMessage = L(.editTooLong)
            return
        }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                guard let did = app.session?.did else { throw ATProtoError.notAuthenticated }

                // Start from the stored record so images that were not touched survive.
                var record = existing ?? ProfileRecord()
                record.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                record.description = about.trimmingCharacters(in: .whitespacesAndNewlines)

                if let avatar {
                    record.avatar = try await app.client.uploadBlob(data: avatar.data,
                                                                    mimeType: "image/jpeg")
                }
                if let banner {
                    record.banner = try await app.client.uploadBlob(data: banner.data,
                                                                    mimeType: "image/jpeg")
                }

                try await app.client.putProfile(did: did, record: record)
                await app.loadOwnProfile()
                dismiss()
            } catch {
                errorMessage = (error as? ATProtoError)?.errorDescription ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
