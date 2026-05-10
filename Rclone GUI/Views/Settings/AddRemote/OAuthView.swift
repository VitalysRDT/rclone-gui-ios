//
//  OAuthView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 3: guides the user to obtain an API key / token from the provider
//  and paste it into the wizard. NO interactive OAuth runs in-app.
//
//  For each backend with `oauthConfig != nil`:
//   1. Show backend hero + setup steps from `OAuthProviderConfig.setupSteps`.
//   2. Offer a Safari link to `setupURL` so the user can mint the token.
//   3. Ask for the value in a TextEditor (multi-line for JSON).
//   4. Validate either as JSON token (rclone format) or as a plain string,
//      based on `tokenFieldName`.
//   5. Write the value into `WizardState.fieldValues[tokenFieldName]`.
//
//  The view is intentionally provider-agnostic: every backend uses the
//  same UI shell and pulls its tutorial from the static config.
//

import SwiftUI

struct OAuthView: View {

    @Bindable var state: WizardState

    let onNext: () -> Void

    @State private var pastedValue: String = ""
    @State private var validationError: String?
    @State private var showCopiedConfirmation = false

    var body: some View {
        Form {
            if let backend = state.selectedBackend, let config = backend.oauthConfig {
                heroSection(for: backend, config: config)
                tutorialSection(config: config)
                if let setupURL = config.setupURL {
                    linkSection(url: setupURL, label: linkLabel(for: backend))
                }
                pasteSection(config: config)
                if let validationError {
                    Section {
                        Label(validationError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            } else {
                Section {
                    Label("Aucun backend sélectionné nécessitant une authentification.",
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
        .onAppear {
            // Pre-populate from any earlier paste in this wizard session.
            if let backend = state.selectedBackend, let config = backend.oauthConfig {
                pastedValue = state.fieldValues[config.tokenFieldName] ?? ""
            }
        }
    }

    // MARK: - Sections

    private func heroSection(for backend: BackendSchema, config: OAuthProviderConfig) -> some View {
        Section {
            VStack(spacing: 12) {
                AppIconTile(systemImage: backend.icon, size: 64, iconSize: .largeTitle)
                Text("Authentifier \(backend.displayName)")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Cette app ne réalise pas d'OAuth interactif. Tu vas obtenir un token / clé API chez \(backend.displayName), puis le coller ici.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private func tutorialSection(config: OAuthProviderConfig) -> some View {
        Section("Comment obtenir le token") {
            if config.setupSteps.isEmpty {
                Text("Aucune procédure documentée. Voir la doc rclone du backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(config.setupSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.tint)
                            .frame(width: 22, alignment: .leading)
                        Text(step)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func linkSection(url: URL, label: String) -> some View {
        Section {
            Link(destination: url) {
                HStack {
                    Image(systemName: "safari.fill")
                    Text(label)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(url.absoluteString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func pasteSection(config: OAuthProviderConfig) -> some View {
        Section {
            TextEditor(text: $pastedValue)
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 100)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: pastedValue) { _, _ in
                    state.oauthCompleted = false
                    validationError = nil
                }

            if let hint = config.tokenHint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                applyPastedValue(config: config)
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
            .disabled(pastedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(config.tokenLabel)
        }
    }

    // MARK: - Actions

    private func applyPastedValue(config: OAuthProviderConfig) {
        let trimmed = pastedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "Coller une valeur d'abord."
            return
        }

        let valueToStore: String

        if config.tokenFieldName == "token" {
            if trimmed.hasPrefix("{") {
                // Looks like a JSON token (rclone authorize output). Validate
                // the shape so the user sees a clean error early.
                do {
                    _ = try OAuthBrokerService.shared.parseManualToken(trimmed)
                    valueToStore = trimmed
                } catch {
                    validationError = error.localizedDescription
                    return
                }
            } else {
                // Raw access_token (e.g. Dropbox `sl.B...`, Yandex hex). Wrap
                // it into the rclone JSON token format so config/create
                // doesn't reject it.
                valueToStore = wrapRawAccessTokenAsJSON(trimmed)
            }
        } else {
            // access_token / api_key / password / permanent_token / etc. —
            // these go in their dedicated rclone field as plain string.
            valueToStore = trimmed
        }

        state.fieldValues[config.tokenFieldName] = valueToStore
        state.oauthCompleted = true
        validationError = nil
    }

    /// Wraps a raw access_token (no JSON envelope) into the rclone-expected
    /// `{"access_token":"...","token_type":"Bearer","refresh_token":"","expiry":"..."}`
    /// shape. Refresh token is empty (the token won't auto-refresh — the
    /// user will need to regenerate it when it expires, which is fine for
    /// long-lived dev tokens like Dropbox's).
    private func wrapRawAccessTokenAsJSON(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let farFutureExpiry = formatter.string(from: Date(timeIntervalSinceNow: 60 * 60 * 24 * 365 * 10))
        let token = RcloneTokenJSON(
            accessToken: raw,
            tokenType: "Bearer",
            refreshToken: "",
            expiry: farFutureExpiry,
            expiresIn: nil
        )
        return (try? token.encodeToJSON()) ?? raw
    }

    // MARK: - Helpers

    private func linkLabel(for backend: BackendSchema) -> String {
        "Ouvrir la page \(backend.displayName)"
    }
}
