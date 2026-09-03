//
//  MacControls.swift
//  Relays
//
//  On iOS a Menu and a compact DatePicker look like the system, which is what
//  people expect there. On macOS the same two draw a bordered pop-up button and
//  a white stepper field — system furniture dropped into a themed window.
//
//  These give macOS the app's own chrome and leave iOS alone.
//

import SwiftUI

#if os(macOS)

/// A button drawn by the app that opens a panel drawn by the app.
struct AppPopover<Label: View, Content: View>: View {
    @ViewBuilder var label: Label
    @ViewBuilder var content: (@escaping () -> Void) -> Content

    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: { label }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    content { isOpen = false }
                }
                .padding(6)
                .frame(minWidth: 200)
                .background(Theme.Palette.surfaceRaised)
            }
    }
}

/// One line in an `AppPopover`: the app's type, the app's spacing, a tick where
/// something is chosen.
struct AppPopoverRow: View {
    let title: String
    var systemImage: String?
    var isSelected = false
    var isDestructive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12))
                        .frame(width: 15)
                }
                Text(title)
                    .font(Theme.Font.ui(13))
                Spacer(minLength: 10)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(isDestructive ? Theme.Palette.danger : Theme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Theme.Palette.surface : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// A date shown in the app's own field, edited in a calendar on the app's own
/// surface — rather than a white stepper sitting in the middle of a themed sheet.
struct AppDateField: View {
    let title: String
    @Binding var date: Date
    var range: PartialRangeThrough<Date> = ...Date()

    @State private var isOpen = false

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textPrimary)

            Spacer(minLength: 8)

            Button { isOpen.toggle() } label: {
                HStack(spacing: 8) {
                    Text(Self.formatted(date))
                        .font(Theme.Font.mono(12))
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.Palette.surface)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                DatePicker("", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.Palette.accent)
                    .padding(12)
                    .background(Theme.Palette.surfaceRaised)
            }
        }
    }

    /// In the reader's language, without the time nobody entered.
    private static func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Format.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#endif
