//
//  OAuthView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 3 (conditional): handles the three OAuth strategies
//  (.customScheme, .universalLink, .manual). Talks to the
//  OAuthBrokerService and writes the resulting token JSON straight
//  into `WizardState.fieldValues["token"]`.
//

import SwiftUI

struct OAuthView: View {

    @Bindable var state: WizardState

    let onNext: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var manualTokenJSON: String = ""
    @State private var showAdvanced = false

    var body: some View {
        Form {
            if let backend = state.selectedBackend, let config = backend.oauthConfig {
                heroSection(for: backend)
                strategySection(for: backend, config: config)
                if showAdvanced {
                    advancedSection(for: config)
                } else {
                    Section {
                        Button {
                            withAnimation { showAdvanced = true }
                        } label: {
                            Label("Configuration OAuth avancée", systemImage: "gearshape.2")
                        }
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Section {
                    Label("Aucun backend OAuth sélectionné.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Suivant") { onNext() }
                    .disabled(!state.oauthCompleted)
            }
        }
    }

    // MARK: - Sections

    private func heroSection(for backend: BackendSchema) -> some View {
        Section {
            VStack(spacing: 12) {
                AppIconTile(systemImage: backend.icon, size: 64, iconSize: .largeTitle)
                Text("Connexion à \(backend.displayName)")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(heroSubtitle(for: backend))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func strategySection(for backend: BackendSchema, config: OAuthProviderConfig) -> some View {
        switch config.strategy {
        case .customScheme:
            Section {
                Button {
                    Task { await runAutoFlow(config: config) }
                } label: {
                    if isAuthenticating {
                        HStack {
                            ProgressView()
                            Text("Authentification…")
                        }
                    } else if state.oauthCompleted {
                        Label("Authentifié — re-authentifier", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Se connecter à \(backend.displayName)")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
            }

        case .universalLink:
            Section {
                Label(
                    "Drive et OneDrive nécessitent un domaine HTTPS configuré (Universal Links). Disponible en P1. Utilise « Coller token » ci-dessous en attendant.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            manualSection(config: config)

        case .manual:
            manualSection(config: config)
        }
    }

    private func manualSection(config: OAuthProviderConfig) -> some View {
        Section {
            Text("""
                 1. Sur un poste avec navigateur, lance :
                 \trclone authorize \"\(config.backendName)\"
                 2. Copie la ligne JSON qui s'affiche.
                 3. Colle-la ci-dessous.
                 """)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $manualTokenJSON)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 100)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button {
                applyManualToken()
            } label: {
                if state.oauthCompleted {
                    Label("Token validé", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Valider le token")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manualTokenJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Coller un token rclone")
        }
    }

    private func advancedSection(for config: OAuthProviderConfig) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Client ID personnel (optionnel)")
                    .font(.caption.weight(.semibold))
                TextField(config.defaultClientID, text: $state.customClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.callout, design: .monospaced))
                Text("Recommandé pour les backends à quotas (Drive, OneDrive). Voir docs rclone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Client secret personnel")
                    .font(.caption.weight(.semibold))
                SecureField("Optionnel", text: $state.customClientSecret)
            }
        } header: {
            Text("Configuration OAuth avancée")
        }
    }

    // MARK: - Actions

    private func runAutoFlow(config: OAuthProviderConfig) async {
        isAuthenticating = true
        errorMessage = nil
        defer { isAuthenticating = false }

        do {
            let token = try await OAuthBrokerService.shared.authenticate(
                config: config,
                customClientID: state.customClientID,
                customClientSecret: state.customClientSecret
            )
            try applyToken(token)
        } catch let error as OAuthBrokerService.BrokerError where error == .canceled {
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "wizard.oauth",
                message: "OAuth failed for \(config.backendName): \(error.localizedDescription)"
            )
        }
    }

    private func applyManualToken() {
        errorMessage = nil
        do {
            let token = try OAuthBrokerService.shared.parseManualToken(manualTokenJSON)
            try applyToken(token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyToken(_ token: RcloneTokenJSON) throws {
        let json = try token.encodeToJSON()
        state.fieldValues["token"] = json
        state.oauthCompleted = true
        state.oauthError = nil
    }

    // MARK: - Helpers

    private func heroSubtitle(for backend: BackendSchema) -> String {
        switch backend.oauthConfig?.strategy {
        case .customScheme:
            return "Tu vas être redirigé vers la page d'authentification. Une fois connecté, tu reviendras automatiquement ici."
        case .universalLink, .manual, .none:
            return "Token requis. Suis les instructions ci-dessous."
        }
    }
}
