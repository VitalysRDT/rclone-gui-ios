//
//  RecapAndTestView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 4: shows a recap of all the values the user is about to write
//  to rclone.conf, runs a connection test, then commits.
//
//  Flow:
//  1. "Tester la connexion" calls `config/create` (writing the section
//     to rclone.conf) followed by `operations/list`. We mark
//     `state.remoteWasPreCreated = true` so a Cancel later cleans up
//     via `config/delete`.
//  2. "Créer le remote" calls `RcloneConfigEditor.refreshRuntimeAndNotify`
//     which re-encrypts ConfigStore + reloads engine + posts the
//     `rcloneConfigurationDidChange` notification, then dismisses.
//

import SwiftUI

struct RecapAndTestView: View {

    @Bindable var state: WizardState

    let onCreated: () -> Void

    @State private var isTesting = false
    @State private var isFinalizing = false

    // Post-config question raised by rclone's non-interactive state machine
    // (e.g. iCloud Drive `config_2fa`). The continuation resumes the
    // ConfigCreateFlow loop with the user's answer (nil = cancel).
    @State private var pendingQuestion: PendingConfigQuestion?
    @State private var questionAnswer = ""

    private struct PendingConfigQuestion: Identifiable {
        let id = UUID()
        let option: RcloneOptionSchema
        let lastError: String?
        let continuation: CheckedContinuation<String?, Never>
    }

    var body: some View {
        Form {
            if let backend = state.selectedBackend {
                summarySection(for: backend)
                parametersSection(for: backend)
                testSection
                actionsSection
            } else {
                Section {
                    Label("Aucun backend sélectionné.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .alert(
            questionTitle(for: pendingQuestion?.option),
            isPresented: Binding(
                get: { pendingQuestion != nil },
                set: { presented in
                    if !presented { resolveQuestion(with: nil) }
                }
            ),
            presenting: pendingQuestion
        ) { question in
            TextField(questionTitle(for: question.option), text: $questionAnswer)
                .rgNoAutocap()
                .autocorrectionDisabled()
            Button("Valider") {
                resolveQuestion(with: questionAnswer)
            }
            Button("Annuler", role: .cancel) {
                resolveQuestion(with: nil)
            }
        } message: { question in
            if let lastError = question.lastError, !lastError.isEmpty {
                Text("\(lastError)\n\n\(question.option.help)")
            } else {
                Text(question.option.help)
            }
        }
        .onDisappear {
            // Never strand the flow's continuation if the wizard is closed
            // while a question is on screen.
            resolveQuestion(with: nil)
        }
    }

    /// Resumes the suspended ConfigCreateFlow exactly once, whichever path
    /// dismisses the alert first (button action, isPresented reset, or the
    /// view disappearing) — a CheckedContinuation must never resume twice.
    private func resolveQuestion(with answer: String?) {
        guard let question = pendingQuestion else { return }
        pendingQuestion = nil
        question.continuation.resume(returning: answer)
    }

    // MARK: - Sections

    private func summarySection(for backend: BackendSchema) -> some View {
        Section {
            HStack(spacing: 14) {
                AppIconTile(systemImage: backend.icon, size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.name)
                        .font(.headline)
                    Text(backend.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if backend.requiresOAuth {
                        Label(state.oauthCompleted ? "Authentifié" : "Authentification requise",
                              systemImage: state.oauthCompleted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(state.oauthCompleted ? .green : .red)
                    }
                }
            }
        }
    }

    private func parametersSection(for backend: BackendSchema) -> some View {
        let entries = nonSecretParameters(for: backend)
        return Section("Paramètres") {
            if entries.isEmpty {
                Text("Aucun paramètre à afficher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.0) { key, value in
                    HStack(alignment: .firstTextBaseline) {
                        Text(key)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: 140, alignment: .leading)
                        Text(value)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                if hasMaskedSecrets(for: backend) {
                    Label("Champs sensibles masqués", systemImage: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var testSection: some View {
        Section {
            if state.selectedBackend?.name == "iclouddrive" {
                Label("iCloud : après le code 2FA, l'obtention du jeton de session Apple peut prendre plusieurs minutes. Laisse l'écran ouvert pendant le test.",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { await runTest() }
            } label: {
                Group {
                    switch state.testResult {
                    case .notTested:
                        Text("Tester la connexion")
                            .frame(maxWidth: .infinity)
                    case .inProgress:
                        HStack {
                            ProgressView()
                            Text("Test en cours…")
                        }
                    case .success(let count, _):
                        Label("Connexion OK — \(count) éléments", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                    case .failure:
                        Label("Tester à nouveau", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    case .timeout:
                        Label("Tester à nouveau (timeout)", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(isTesting || isFinalizing)

            switch state.testResult {
            case .success(_, let sample):
                if !sample.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(sample, id: \.self) { name in
                            Text("• \(name)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            case .failure(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            case .timeout:
                Label("Le serveur ne répond pas. Vérifie ta connexion ou tes paramètres.",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }
        } header: {
            Text("Validation")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await finalizeCreation() }
            } label: {
                if isFinalizing {
                    HStack {
                        ProgressView()
                        Text(state.isEditing ? "Enregistrement…" : "Création…")
                    }
                } else {
                    Text(state.isEditing ? "Enregistrer les modifications" : "Créer le remote")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canFinalize)
        } footer: {
            if !canFinalize {
                Text(state.isEditing
                     ? "Applique d’abord les modifications et teste la connexion."
                     : "Le remote sera créé après un test réussi. Si le test échoue de manière connue, tu peux quand même créer le remote.")
                    .font(.caption2)
            }
        }
    }

    // MARK: - Computed

    private var canFinalize: Bool {
        guard !isFinalizing else { return false }
        if state.isEditing && !state.configurationWasApplied {
            return false
        }
        switch state.testResult {
        case .success, .failure, .timeout:
            // .failure and .timeout still allow creation (force-create)
            // because the user might know better than us (network blip).
            return true
        case .notTested, .inProgress:
            return false
        }
    }

    private func nonSecretParameters(for backend: BackendSchema) -> [(String, String)] {
        let oauthHidden: Set<String> = ["token", "auth_url", "token_url", "client_secret"]
        var entries: [(String, String)] = []
        for field in backend.formFields {
            if oauthHidden.contains(field.name) { continue }
            if field.sensitive || field.isPassword { continue }
            let value = state.fieldValues[field.name] ?? ""
            guard !value.isEmpty else { continue }
            entries.append((field.label, value))
        }
        return entries
    }

    private func hasMaskedSecrets(for backend: BackendSchema) -> Bool {
        backend.formFields.contains { field in
            (field.sensitive || field.isPassword) && !(state.fieldValues[field.name] ?? "").isEmpty
        }
    }

    // MARK: - Actions

    private func runTest() async {
        guard let backend = state.selectedBackend else { return }
        isTesting = true
        state.testResult = .inProgress
        defer { isTesting = false }

        // 1. Pre-create the remote in rclone.conf so operations/list works.
        do {
            if state.isEditing {
                try await updateExistingRemote(backend: backend)
                state.configurationWasApplied = true
            } else {
                try await callConfigCreate(backend: backend)
                state.remoteWasPreCreated = true
            }
        } catch {
            state.testResult = .failure(message: error.localizedDescription)
            return
        }

        // 2. Run operations/list with timeout. iCloud gets a much longer
        // window: right after 2FA, Apple can take minutes to mint the
        // session token before the first listing answers.
        let timeoutSeconds = backend.name == "iclouddrive" ? 180 : 10
        do {
            let result = try await RemoteConnectionTester.test(
                remote: state.name,
                timeoutSeconds: timeoutSeconds
            )
            state.testResult = .success(itemCount: result.itemCount, sample: result.sample)
        } catch RemoteConnectionTester.TestError.timeout(let secs) {
            state.testResult = .timeout
            await LogService.shared.log(
                .error,
                category: "wizard.test",
                message: "Test connection timeout (\(secs)s) for \(state.name)"
            )
        } catch {
            state.testResult = .failure(message: error.localizedDescription)
            await LogService.shared.log(
                .error,
                category: "wizard.test",
                message: "Test failed for \(state.name): \(error.localizedDescription)"
            )
        }
    }

    private func callConfigCreate(backend: BackendSchema) async throws {
        // Build parameters dict from non-empty form values.
        var params: [String: String] = [:]
        for (key, value) in state.fieldValues {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            params[key] = trimmed
        }

        // If we already pre-created on a previous test attempt, drop
        // the orphan first so config/create succeeds. Keep the flag
        // set if the delete fails — handleCancel will retry on the
        // way out so we don't permanently strand a section we own.
        if state.remoteWasPreCreated {
            struct DeleteInput: Encodable { let name: String }
            let json = (try? JSONEncoder().encode(DeleteInput(name: state.name)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            do {
                _ = try await RcloneCore.shared.rpcRaw("config/delete", json)
                state.remoteWasPreCreated = false
            } catch {
                // Leave remoteWasPreCreated = true so cancel still cleans up.
                await LogService.shared.log(
                    .error,
                    category: "wizard",
                    message: "Failed to delete orphan \(state.name) before retry: \(error.localizedDescription)"
                )
            }
        }

        // rclone stocke les champs « password » obscurcis (obscure.Obscure) et
        // les révèle au runtime. Si on écrit un mot de passe EN CLAIR sans
        // obscure=true, rclone échoue à le révéler à la connexion. On demande
        // donc l'obscurcissement dès qu'un paramètre correspond à un champ que
        // rclone marque isPassword : crypt (password/password2) mais aussi
        // `pass` (sftp/ftp/webdav/smb/mailru/internxt), `password` + `api_key`
        // (filen), etc. obscure=true n'agit QUE sur les champs IsPassword du
        // backend — sans effet sur les autres paramètres.
        let passwordFieldNames = Set(
            backend.fields.filter { $0.isPassword }.map(\.name)
        )
        let needsObscure = backend.name == "crypt"
            || params.keys.contains { passwordFieldNames.contains($0) }

        // Some backends (iCloud Drive → config_2fa) answer config/create with
        // follow-up questions instead of completing. ConfigCreateFlow loops on
        // the state machine, surfacing each question via askQuestion (alert).
        let flow = ConfigCreateFlow(rpc: { method, input in
            try await RcloneCore.shared.rpc(method, input: input)
        })
        try await flow.run(
            name: state.name,
            type: backend.name,
            parameters: params,
            obscure: needsObscure,
            onRemoteWritten: {
                // A (possibly partial) section now exists in rclone.conf —
                // arm the config/delete cleanup even if a question is
                // cancelled or fails after this point.
                state.remoteWasPreCreated = true
            },
            ask: { option, lastError in
                await askQuestion(option, lastError: lastError)
            }
        )
        await RcloneCore.shared.invalidateConfigCache()
    }

    private func updateExistingRemote(backend: BackendSchema) async throws {
        var params: [String: String] = [:]
        for (key, value) in state.fieldValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            params[key] = trimmed
        }
        let passwordFieldNames = Set(backend.fields.filter(\.isPassword).map(\.name))
        try await RcloneConfigEditor.updateRemote(
            name: state.name,
            type: backend.name,
            options: params,
            obscure: params.keys.contains { passwordFieldNames.contains($0) },
            ask: { option, lastError in
                await askQuestion(option, lastError: lastError)
            }
        )
    }

    /// Suspends the ConfigCreateFlow loop while the alert collects the
    /// user's answer to a post-config question (nil = cancelled).
    private func askQuestion(_ option: RcloneOptionSchema, lastError: String?) async -> String? {
        await withCheckedContinuation { continuation in
            questionAnswer = ""
            pendingQuestion = PendingConfigQuestion(
                option: option,
                lastError: lastError,
                continuation: continuation
            )
        }
    }

    private func questionTitle(for option: RcloneOptionSchema?) -> String {
        switch option?.name {
        case "config_2fa":
            return String(localized: "Code de vérification Apple (2FA)")
        case nil:
            return String(localized: "Question rclone")
        case .some(let name):
            return name
        }
    }

    private func finalizeCreation() async {
        isFinalizing = true
        defer { isFinalizing = false }

        if state.isEditing {
            await LogService.shared.log(
                .info,
                category: "wizard",
                message: "Remote « \(state.name) » modifié via wizard"
            )
            onCreated()
            return
        }

        // If the test ran, the remote is already in rclone.conf via
        // librclone's own write. We still need to sync ConfigStore
        // (re-encrypt) and notify the rest of the app.
        if !state.remoteWasPreCreated, let backend = state.selectedBackend {
            do {
                try await callConfigCreate(backend: backend)
                state.remoteWasPreCreated = true
            } catch {
                state.configCreateError = error.localizedDescription
                return
            }
        }

        // Re-encrypt the runtime config (now containing the new remote, written
        // by librclone via config/create) back into ConfigStore AVANT le reload.
        // Sans ça, refreshRuntimeAndNotify rechargerait l'ancien store chiffré et
        // le remote fraîchement créé disparaîtrait (bug « ajouté mais pas apparu »).
        do {
            try await ConfigStore.shared.persistRuntimeConfigToStore()
        } catch {
            state.configCreateError = error.localizedDescription
            return
        }

        // Mirror to ConfigStore (re-encrypt) + reload + notifications.
        await RcloneConfigEditor.refreshRuntimeAndNotify()
        await LogService.shared.log(
            .info,
            category: "wizard",
            message: "Remote « \(state.name) » créé via wizard"
        )
        onCreated()
    }
}
