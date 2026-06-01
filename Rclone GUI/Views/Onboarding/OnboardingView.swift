//
//  OnboardingView.swift
//  Rclone GUI — Views/Onboarding
//
//  First-launch onboarding (controlled via @AppStorage("hasCompletedOnboarding")).
//  Implements FR-002 of the PRD with the crypt-first walkthrough design:
//  hero seal → 3 feature bullets → primary "Import rclone.conf" CTA →
//  secondary "Create Crypt Passport" CTA → privacy footer.
//

import Photos
import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    @State private var step: Step = .welcome
    @State private var showImportPicker = false

    enum Step: Hashable {
        case welcome
        case photoSync  // D5
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
                step = .photoSync   // D5 : pivote vers le step PhotoSync au lieu de done
            })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:      welcomeView
        case .photoSync:    photoSyncView
        case .done:         doneView
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
                    // Crypt passport flow lives in Phase E2 ; on enchaîne
                    // directement sur l'écran final. L'essai gratuit 7 jours
                    // tourne déjà en fond — aucun paywall à ce stade.
                    step = .done
                } label: {
                    Text("Créer un Passeport Crypt")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(RG.accent)
                }
                .buttonStyle(.plain)

                Text("Tes clés ne quittent jamais ton appareil")
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

    // MARK: - PhotoSync step (D5)

    /// Présenté après l'import de la config rclone (ou via "Plus tard").
    /// Promotion de la feature PhotoSync : visible, skippable, demande
    /// l'authorization Photos dès le tap "Activer".
    private var photoSyncView: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Hero : seal PhotoSync (gradient pink → deep pink) au lieu
            // du seal violet crypt, pour bien marquer la feature.
            VStack(spacing: 18) {
                photoSyncSeal
                VStack(spacing: 6) {
                    Text("Garde tes photos en sûreté")
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text("PhotoSync — backup automatique")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Text("Sauvegarde toute ta photothèque vers ton remote rclone, en pipeline batché, avec dédup pré-export et reprise auto.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 28).frame(maxHeight: 28)

            // Feature bullets PhotoSync
            VStack(spacing: 14) {
                featureRow(
                    icon: "photo.on.rectangle.angled",
                    tint: RG.photoSync.accent,
                    title: "Backup automatique",
                    subtitle: "Les nouvelles photos sont envoyées en arrière-plan"
                )
                featureRow(
                    icon: "bolt.slash.fill",
                    tint: .green,
                    title: "Wi-Fi + charge par défaut",
                    subtitle: "Pas de surprise data, batterie préservée"
                )
                featureRow(
                    icon: "rectangle.stack.fill.badge.plus",
                    tint: .orange,
                    title: "Choisis tes albums",
                    subtitle: "Backup ciblé ou photothèque complète"
                )
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    Task { await enablePhotoSync() }
                } label: {
                    Text("Activer PhotoSync")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RG.photoSync.accent, in: RoundedRectangle(cornerRadius: RG.Radius.card, style: .continuous))
                        .foregroundStyle(.white)
                        .shadow(color: RG.photoSync.accent.opacity(0.30), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)

                Button {
                    step = .done
                } label: {
                    Text("Plus tard")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("Tu peux modifier tout ça plus tard dans Réglages → Synchro Photos")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
        }
    }

    /// Seal personnalisé PhotoSync : gradient pink/accent à la place du
    /// seal violet crypt — réutilise le langage visuel de l'app.
    private var photoSyncSeal: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [RG.photoSync.accent, RG.photoSync.accentDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 120, height: 120)
                .overlay {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 60, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: RG.photoSync.accent.opacity(0.35), radius: 18, x: 0, y: 14)

            Circle()
                .fill(.green)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle().stroke(Color.rgSystemBackground, lineWidth: 3)
                }
                .offset(x: 6, y: -6)
        }
        .frame(width: 126, height: 126, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// Tap "Activer PhotoSync" — demande l'authorization Photos puis
    /// persiste `photoSync.enabled = true`. Si l'authorization est
    /// refusée ou limitée, on bascule quand même au step done (le user
    /// trouvera le bouton "Modifier l'accès aux Photos" dans Réglages).
    @MainActor
    private func enablePhotoSync() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if status == .authorized || status == .limited {
            UserDefaults.standard.set(true, forKey: "photoSync.enabled")
        }
        step = .done
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
