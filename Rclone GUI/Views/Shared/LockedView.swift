//
//  LockedView.swift
//  Rclone GUI — Views/Shared
//
//  Standalone Face ID gate screen — the "02 · Face ID" walkthrough
//  artboard from the design handoff. Presents the violet face-id tile,
//  the localized prompt, and a passcode fallback chip. Used both as a
//  reusable lock screen (when the encrypted rclone.conf needs unlock)
//  and as the in-app preview surfaced by SecuritySettingsView.
//

import SwiftUI

struct LockedView: View {
    /// Localized title — defaults to "Déverrouillez Rclone".
    var title: LocalizedStringKey = "Déverrouillez Rclone"
    /// Localized rationale — what does the user gain by authenticating?
    var subtitle: LocalizedStringKey = "Face ID est requis pour lire votre rclone.conf chiffré."
    /// Triggered when the user taps the primary tile or the passcode pill.
    var onAuthenticate: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Soft violet tile with the face-id glyph
            Button(action: { onAuthenticate?() }) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RG.accentSoft)
                    .frame(width: 88, height: 88)
                    .overlay {
                        Image(systemName: "faceid")
                            .font(.system(size: 44, weight: .regular))
                            .foregroundStyle(RG.accent)
                    }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 26)

            Text(title)
                .font(.system(size: 22, weight: .bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 8)
                .lineSpacing(2)

            Spacer(minLength: 0)
                .frame(maxHeight: 40)

            // Passcode fallback pill (mirrors the design's "⌨ Mot de passe")
            Button(action: { onAuthenticate?() }) {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .medium))
                    Text("Mot de passe")
                        .font(RG.mono)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.quaternary, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Tape pour déverrouiller avec Face ID ou un code")
    }
}

#Preview("Locked — light") {
    LockedView()
}

#Preview("Locked — dark") {
    LockedView()
        .preferredColorScheme(.dark)
}
