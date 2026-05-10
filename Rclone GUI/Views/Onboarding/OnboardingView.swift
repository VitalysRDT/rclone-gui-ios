//
//  OnboardingView.swift
//  Rclone GUI — Views/Onboarding
//
//  First-launch onboarding (controlled via @AppStorage("hasCompletedOnboarding")).
//  Implements FR-002 of the PRD with the crypt-first walkthrough design:
//  hero seal → 3 feature bullets → primary "Import rclone.conf" CTA →
//  secondary "Create Crypt Passport" CTA → privacy footer.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    @State private var step: Step = .welcome
    @State private var showImportPicker = false

    enum Step: Hashable {
        case welcome
        case done
    }

    var body: some View {
        NavigationStack {
            content
                .navigationBarBackButtonHidden(true)
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
        }
        .sheet(isPresented: $showImportPicker) {
            ImportConfigView(onImported: {
                showImportPicker = false
                step = .done
            })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcomeView
        case .done:    doneView
        }
    }

    // MARK: - Welcome (mirrors `01 · Bienvenue` from the design)

    private var welcomeView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Hero crypt seal
            VStack(spacing: 18) {
                RGCryptSeal(size: 120)
                VStack(spacing: 6) {
                    Text("Bienvenue dans Rclone")
                        .font(.system(size: 30, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("Welcome to Rclone")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Text("Tous tes remotes — y compris chiffrés — accessibles depuis Fichiers, en streaming et hors-ligne.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 28).frame(maxHeight: 28)

            // Feature bullets
            VStack(spacing: 14) {
                featureRow(
                    icon: "lock.fill",
                    tint: RG.accent,
                    title: "Crypt rclone natif",
                    subtitle: "AES-256, noms déchiffrés à la volée"
                )
                featureRow(
                    icon: "cloud.fill",
                    tint: .blue,
                    title: "80+ backends",
                    subtitle: "S3, R2, Drive, Dropbox, SFTP, B2…"
                )
                featureRow(
                    icon: "folder.fill",
                    tint: .orange,
                    title: "Intégration Fichiers",
                    subtitle: "Chaque remote = un emplacement natif"
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            // CTAs
            VStack(spacing: 10) {
                Button {
                    showImportPicker = true
                } label: {
                    Text("Importer un rclone.conf")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RG.accent, in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
                        .foregroundStyle(.white)
                        .shadow(color: RG.accent.opacity(0.30), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    // Crypt passport flow lives in Phase E2; for now we just
                    // skip onboarding and let the user reach the empty
                    // remotes state inside the app.
                    step = .done
                } label: {
                    Text("Créer un Passeport Crypt")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(RG.accent)
                }
                .buttonStyle(.plain)

                Text("Tes clés ne quittent jamais l’iPhone")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
    }

    private func featureRow(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            RGCryptSeal(size: 96)
            Text("C’est prêt")
                .font(.system(size: 28, weight: .bold))
            Text("Tu peux maintenant parcourir tes remotes, transférer des fichiers et lire tes médias depuis Fichiers.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer(minLength: 0)
            Button {
                isPresented = false
            } label: {
                Text("Aller à l’app")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RG.accent, in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: RG.accent.opacity(0.30), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
    }
}
