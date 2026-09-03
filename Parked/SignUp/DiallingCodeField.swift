//
//  DiallingCodeField.swift
//  Relays
//
//  The country belongs to the number, so it sits in the same row as the number
//  rather than on a line of its own. Tapping it opens a small window with the
//  248 of them and a place to type — a menu that long is a scroll wheel, not a
//  choice.
//

import SwiftUI

struct DiallingCodeField: View {
    @Binding var region: String
    @Binding var number: String
    var placeholder: String

    @State private var open = false
    @State private var query = ""

    private var selected: DiallingCode { DiallingCode.named(region) ?? DiallingCode.current }

    var body: some View {
        HStack(spacing: 10) {
            Button { open = true } label: {
                HStack(spacing: 6) {
                    Text(selected.flag)
                        .font(.system(size: 15))
                    Text(selected.prefix)
                        .font(Theme.Font.mono(13))
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: Theme.Metric.fieldHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                        .fill(Theme.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metric.cornerRadius, style: .continuous)
                        .stroke(Theme.Palette.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L(.signUpPhoneCountry)): \(selected.name) \(selected.prefix)")
            .popover(isPresented: $open, arrowEdge: .bottom) {
                chooser
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }

            MonoField(icon: "phone", placeholder: placeholder, text: $number)
        }
    }

    // MARK: - The small window

    private var matches: [DiallingCode] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return DiallingCode.sortedByName }
        return DiallingCode.sortedByName.filter {
            $0.name.localizedCaseInsensitiveContains(text)
                || $0.prefix.contains(text)
                || $0.region.localizedCaseInsensitiveContains(text)
        }
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.textTertiary)
                TextField("", text: $query, prompt: Text(L(.signUpPhoneCountry))
                    .foregroundStyle(Theme.Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .tint(Theme.Palette.accent)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Hairline()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { entry in
                        row(entry)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(width: 280, height: 340)
        .background(Theme.Palette.background)
    }

    private func row(_ entry: DiallingCode) -> some View {
        Button {
            region = entry.region
            query = ""
            open = false
        } label: {
            HStack(spacing: 10) {
                Text(entry.flag)
                    .font(.system(size: 15))
                Text(entry.name)
                    .font(Theme.Font.ui(13))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.prefix)
                    .font(Theme.Font.mono(12))
                    .foregroundStyle(Theme.Palette.textTertiary)
                if entry.region == region {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
