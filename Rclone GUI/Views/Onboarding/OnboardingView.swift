//
//  OnboardingView.swift
//  Rclone GUI — Views/Onboarding
//
//  3-step onboarding shown on first launch (controlled via
//  @AppStorage("hasCompletedOnboarding")). Implements FR-002 of the PRD :
//  crypt-first design — the second step nudges (but doesn't force) the
//  user to create a Crypt Passport.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    @State private var step: Step = .welcome
    @State private var showImportPicker = false

    enum Step: Hashable {
        case welcome
        case configChoice
        case done
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                navigationFooter
                    .padding()
            }
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $showImportPicker) {
            ImportConfigView(onImported: {
                showImportPicker = false
                step = .done
            })
        }
    }

    private var navigationTitle: String {
        switch step {
        case .welcome:      return "Bienvenue"
        case .configChoice: return "Configuration"
        case .done:         return "C'est prêt"
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcomeView
        case .configChoice: configChoiceView
        case .done: doneView
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity)
                .padding(.bottom)

            Text("Rclone GUI")
                .font(.largeTitle.bold())

            Text("Le client iOS natif pour rclone : tous tes remotes, navigation native Files.app, support transparent des remotes chiffrés `crypt`.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer().frame(height: 24)

            featureRow("externaldrive", "Tous les backends",
                       "S3, R2, Bunny, B2, SFTP, WebDAV, Drive, Dropbox, OneDrive…")
            featureRow("lock.shield", "Crypt natif",
                       "Décryptage transparent des remotes `crypt` rclone")
            featureRow("arrow.up.arrow.down.circle", "Transferts robustes",
                       "Reprise après kill, queue persistante, opérations server-side")
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Config choice

    private var configChoiceView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Comment veux-tu commencer ?")
                .font(.title2.bold())

            VStack(spacing: 12) {
                Button {
                    showImportPicker = true
                } label: {
                    OnboardingChoiceCard(
                        icon: "square.and.arrow.down",
                        title: "Importer mon rclone.conf",
                        subtitle: "Chiffré ou non, depuis Files / iCloud / AirDrop",
                        isPrimary: true
                    )
                }
                .buttonStyle(.plain)

                Button {
                    step = .done
                } label: {
                    OnboardingChoiceCard(
                        icon: "lock.shield",
                        title: "Créer un Passeport Crypt",
                        subtitle: "Identité chiffrée + premier remote crypt (Phase E2)",
                        isPrimary: false,
                        isDisabled: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(true)

                Button {
                    step = .done
                } label: {
                    OnboardingChoiceCard(
                        icon: "questionmark.circle",
                        title: "Continuer sans configuration",
                        subtitle: "Tu pourras importer ou créer plus tard",
                        isPrimary: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("C'est prêt")
                .font(.title.bold())
            Text("Tu peux maintenant naviguer dans tes remotes, télécharger, et lire tes médias depuis l'onglet Remotes.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var navigationFooter: some View {
        switch step {
        case .welcome:
            Button {
                step = .configChoice
            } label: {
                Text("Commencer").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .configChoice:
            Button("Plus tard") { step = .done }
                .controlSize(.large)
        case .done:
            Button {
                isPresented = false
            } label: {
                Text("Aller aux remotes").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct OnboardingChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    var isPrimary: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(isDisabled ? AnyShapeStyle(.secondary) : (isPrimary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.tint)))
                .frame(width: 56, height: 56)
                .background(isPrimary ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial))
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()

            if !isDisabled {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            } else {
                Text("Bientôt")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: .capsule)
            }
        }
        .padding()
        .background(.thinMaterial, in: .rect(cornerRadius: 14))
    }
}
