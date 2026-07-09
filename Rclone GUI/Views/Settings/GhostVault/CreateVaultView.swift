//
//  CreateVaultView.swift
//  Rclone GUI — Views/Settings
//
//  Wizard de création d'un Ghost Vault : choix du remote + dossier +
//  passphrase, scellé par Face ID / Touch ID / mot de passe iCloud.
//

import SwiftUI

struct CreateVaultView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .remote
    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var loadingRemotes = true
    @State private var selectedRemote: RemoteSummaryDTO?
    @State private var selectedFolder: String = GhostVault.remoteFolder
    @State private var passphrase: String = ""
    @State private var passphraseConfirm: String = ""
    @State private var biometricsAvailable = true
    @State private var submitting = false
    @State private var submitError: String?
    @State private var success: GhostVaultCreateResult?
    @State private var showFolderPicker = false

    enum Step: Hashable {
        case remote
        case passphrase
        case seal
        case done
    }

    var body: some View {
        Form {
            switch step {
            case .remote:
                remoteSection
            case .passphrase:
                passphraseSection
            case .seal:
                sealSection
            case .done:
                doneSection
            }

            if let error = submitError {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Créer un vault")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
                    .disabled(submitting)
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            if let remote = selectedRemote {
                NavigationStack {
                    GhostVaultFolderPicker(remote: remote.name, initial: selectedFolder) { folder in
                        selectedFolder = folder
                        showFolderPicker = false
                    }
                }
            }
        }
        .task {
            await loadRemotes()
            biometricsAvailable = await BiometricGate.shared.isAvailable()
        }
    }

    // MARK: Sections

    private var remoteSection: some View {
        Group {
            Section {
                if loadingRemotes {
                    HStack {
                        ProgressView()
                        Text("Chargement des remotes…").foregroundStyle(.secondary)
                    }
                } else if remotes.isEmpty {
                    Text("Aucun remote configuré. Ajoute d'abord un remote dans Réglages → Configuration.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remotes) { remote in
                        Button {
                            selectedRemote = remote
                        } label: {
                            HStack {
                                Image(systemName: remote.isCrypt ? "lock.fill" : "externaldrive.fill")
                                    .foregroundStyle(remote.isCrypt ? .indigo : .blue)
                                VStack(alignment: .leading) {
                                    Text(remote.name).foregroundStyle(.primary)
                                    Text(remote.type + (remote.isCrypt ? " · déjà chiffré (on chiffre quand même)" : ""))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedRemote?.id == remote.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.indigo)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Remote de destination")
            } footer: {
                if let remote = selectedRemote {
                    Text("Vault écrit dans \(remote.name):\(selectedFolder.isEmpty ? "/" : selectedFolder)/ghost-vault-AAAA-MM-JJ.rclonebackup")
                } else {
                    Text("On chiffre TOUJOURS côté client, même si le remote est déjà un `crypt` rclone.")
                }
            }

            if let remote = selectedRemote {
                Section {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack {
                            Label("Dossier dans le remote", systemImage: "folder.fill")
                            Spacer()
                            Text(selectedFolder.isEmpty ? "/" : selectedFolder)
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Emplacement")
                } footer: {
                    Text("Par défaut : \(GhostVault.remoteFolder)/. Tu peux créer un sous-dossier si tu ranges tes backups.")
                }

                Section {
                    Button {
                        step = .passphrase
                    } label: {
                        Text("Continuer")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
    }

    private var passphraseSection: some View {
        Group {
            Section {
                SecureField("Passphrase (min. \(GhostVault.minPassphraseLength) caractères)", text: $passphrase)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                SecureField("Confirmer la passphrase", text: $passphraseConfirm)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Passphrase")
            } footer: {
                Text("La passphrase sert à chiffrer le vault. Elle ne quitte jamais l'appareil et ne peut pas être récupérée — choisis-la longue (phrase + chiffres) et conserve-la dans un endroit sûr (gestionnaire de mots de passe).")
            }

            Section {
                Toggle("Afficher les critères", isOn: .constant(false))
                    .disabled(true)
                ForEach(passphraseChecks, id: \.label) { check in
                    HStack(spacing: 8) {
                        Image(systemName: check.ok ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(check.ok ? .green : .secondary)
                        Text(check.label)
                            .font(.caption)
                            .foregroundStyle(check.ok ? .primary : .secondary)
                    }
                }
            } header: {
                Text("Critères")
            }

            Section {
                Button {
                    Task { await seal() }
                } label: {
                    if submitting {
                        HStack { ProgressView(); Text("Scellement…") }
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sceller et uploader")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!passphraseIsValid || submitting)

                Button("Retour") { step = .remote }
                    .disabled(submitting)
            }
        }
    }

    private var sealSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Scellement et upload en cours…")
            }
        } footer: {
            Text("Face ID / Touch ID est demandé pour confirmer l'opération.")
        }
    }

    private var doneSection: some View {
        Section {
            if let result = success {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Vault créé", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Emplacement :")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(result.descriptor.remote):\(result.descriptor.remotePath)")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text("Taille : \(ByteCountFormatter.string(fromByteCount: Int64(result.descriptor.sizeBytes), countStyle: .file))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Button("Terminé") { dismiss() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Helpers

    private var passphraseChecks: [(label: String, ok: Bool)] {
        [
            ("Au moins \(GhostVault.minPassphraseLength) caractères", passphrase.count >= GhostVault.minPassphraseLength),
            ("Confirmation identique", passphrase == passphraseConfirm && !passphrase.isEmpty)
        ]
    }

    private var passphraseIsValid: Bool {
        passphrase.count >= GhostVault.minPassphraseLength && passphrase == passphraseConfirm
    }

    private func loadRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
        } catch {
            remotes = []
        }
    }

    private func seal() async {
        guard let remote = selectedRemote else { return }
        submitError = nil
        step = .seal
        let biometricResult = await BiometricGate.shared.authenticate(reason: .ghostVaultSeal)
        guard biometricResult == .authenticated else {
            step = .passphrase
            if case .userCancelled = biometricResult {
                // L'utilisateur a annulé — on reste sur l'écran sans erreur
                return
            }
            if case .unavailable(let msg) = biometricResult {
                submitError = msg
            } else {
                submitError = "Authentification annulée."
            }
            return
        }
        submitting = true
        defer {
            submitting = false
            if step == .seal && submitError == nil {
                step = .passphrase
            }
        }
        do {
            let result = try await GhostVaultService.shared.create(
                request: GhostVaultCreateRequest(
                    remote: remote.name,
                    folder: selectedFolder,
                    passphrase: passphrase
                )
            )
            success = result
            step = .done
        } catch {
            submitError = error.localizedDescription
            step = .passphrase
        }
    }
}

/// Petit navigateur de dossier adapté à Ghost Vault : on choisit un dossier
/// dans le remote, on n'autorise que les dossiers (pas de fichier), et le
/// bouton "Choisir" est toujours disponible pour valider le dossier courant.
private struct GhostVaultFolderPicker: View {
    let remote: String
    let initial: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String] = []

    var body: some View {
        NavigationStack(path: $pathStack) {
            GhostVaultFolderLevel(remote: remote, path: "", onPick: onPick)
                .navigationTitle("\(remote):")
                .navigationDestination(for: String.self) { p in
                    GhostVaultFolderLevel(remote: remote, path: p, onPick: onPick)
                        .navigationTitle((p as NSString).lastPathComponent)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
        }
    }
}

private struct GhostVaultFolderLevel: View {
    let remote: String
    let path: String
    let onPick: (String) -> Void

    @State private var entries: [RemoteEntryDTO] = []
    @State private var loading = true
    @State private var error: String?

    private var directories: [RemoteEntryDTO] {
        entries.filter(\.isDirectory)
    }

    var body: some View {
        List {
            Section {
                Button {
                    onPick(path)
                } label: {
                    Label(
                        path.isEmpty ? "Choisir la racine" : "Choisir « \(path) »",
                        systemImage: "checkmark.circle.fill"
                    )
                }
            }
            Section("Sous-dossiers") {
                if loading {
                    HStack { ProgressView(); Text("Chargement…").foregroundStyle(.secondary) }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                } else if directories.isEmpty {
                    Text("Aucun sous-dossier ici.").foregroundStyle(.secondary)
                } else {
                    ForEach(directories) { dir in
                        NavigationLink(value: dir.pathInRemote) {
                            Label(dir.name, systemImage: "folder")
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await RemoteService.shared.list(remote: remote, path: path)
        } catch {
            self.error = error.localizedDescription
        }
    }
}