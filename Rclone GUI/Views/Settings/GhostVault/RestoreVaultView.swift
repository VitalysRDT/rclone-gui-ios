//
//  RestoreVaultView.swift
//  Rclone GUI — Views/Settings
//
//  Wizard de restauration d'un Ghost Vault : scan d'un remote pour lister
//  les vaults, saisie de la passphrase, déverrouillage biométrique, confirmation
//  avant d'écraser le rclone.conf actuel.
//

import SwiftUI

struct RestoreVaultView: View {
    @Environment(\.dismiss) private var dismiss

    let initial: GhostVaultDescriptor?

    @State private var step: Step = .list
    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var selectedRemote: RemoteSummaryDTO?
    @State private var folder: String = GhostVault.remoteFolder
    @State private var scanned: [GhostVaultDescriptor] = []
    @State private var loadingScan = false
    @State private var selectedVault: GhostVaultDescriptor?
    @State private var passphrase: String = ""
    @State private var biometricsAvailable = true
    @State private var submitting = false
    @State private var submitError: String?
    @State private var restoredBytes: Int?
    @State private var showConfirmReplace = false
    @State private var manifest: [GhostVaultDescriptor] = []
    @State private var showFolderPicker = false

    enum Step: Hashable {
        case list
        case passphrase
        case confirm
        case done
    }

    var body: some View {
        Form {
            switch step {
            case .list:
                listSection
            case .passphrase:
                passphraseSection
            case .confirm:
                confirmSection
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
        .navigationTitle("Restaurer un vault")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
                    .disabled(submitting)
            }
        }
        .task {
            await loadRemotes()
            await loadManifest()
            biometricsAvailable = await BiometricGate.shared.isAvailable()
            if let initial = initial {
                selectedVault = initial
                selectedRemote = remotes.first(where: { $0.name == initial.remote })
                step = .passphrase
            }
        }
        .sheet(isPresented: $showFolderPicker) {
            if let remote = selectedRemote {
                NavigationStack {
                    GhostVaultFolderPickerRestore(remote: remote.name, initial: folder) { picked in
                        folder = picked
                        showFolderPicker = false
                        Task { await scan(remote: remote.name, folder: picked) }
                    }
                }
            }
        }
        .alert("Remplacer la configuration actuelle ?", isPresented: $showConfirmReplace) {
            Button("Restaurer", role: .destructive) {
                Task { await performRestore() }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let v = selectedVault {
                Text("Le vault « \(v.filename) » (\(v.remoteCount) remote\(v.remoteCount > 1 ? "s" : "")) remplacera la configuration actuelle. Cette action est irréversible — pense à faire un nouveau vault d'abord si tu veux garder l'ancienne.")
            } else {
                Text("Cette action est irréversible.")
            }
        }
    }

    // MARK: Sections

    private var listSection: some View {
        Group {
            Section {
                if let initial = initial {
                    VaultPickerRow(
                        descriptor: initial,
                        selected: selectedVault?.id == initial.id
                    ) {
                        selectedVault = initial
                        step = .passphrase
                    }
                } else {
                    if remotes.isEmpty && !loadingScan {
                        Text("Aucun remote configuré.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Remote", selection: $selectedRemote) {
                            Text("Choisir…").tag(RemoteSummaryDTO?.none)
                            ForEach(remotes) { remote in
                                Text(remote.name).tag(RemoteSummaryDTO?.some(remote))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if let remote = selectedRemote {
                        Button {
                            showFolderPicker = true
                        } label: {
                            HStack {
                                Label("Dossier", systemImage: "folder.fill")
                                Spacer()
                                Text(folder.isEmpty ? "/" : folder)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.right")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await scan(remote: remote.name, folder: folder) }
                        } label: {
                            HStack {
                                if loadingScan { ProgressView() }
                                Text(loadingScan ? "Scan en cours…" : "Scanner ce dossier")
                            }
                        }
                        .disabled(loadingScan)

                        if !scanned.isEmpty {
                            ForEach(scanned) { descriptor in
                                VaultPickerRow(
                                    descriptor: descriptor,
                                    selected: selectedVault?.id == descriptor.id
                                ) {
                                    selectedVault = descriptor
                                    step = .passphrase
                                }
                            }
                        } else if !loadingScan {
                            Text("Aucun vault trouvé dans \(remote.name):\(folder.isEmpty ? "/" : folder)/")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !manifest.isEmpty {
                        Section {
                            ForEach(manifest) { descriptor in
                                VaultPickerRow(
                                    descriptor: descriptor,
                                    selected: selectedVault?.id == descriptor.id
                                ) {
                                    selectedVault = descriptor
                                    step = .passphrase
                                }
                            }
                        } header: {
                            Text("Vaults connus sur cet appareil")
                        }
                    }
                }
            } header: {
                Text("Vault à restaurer")
            }
        }
    }

    private var passphraseSection: some View {
        Group {
            if let v = selectedVault {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.filename).font(.subheadline.weight(.semibold))
                        Text("\(v.remoteCount) remote\(v.remoteCount > 1 ? "s" : "") • créé le \(v.createdAt.formatted(date: .abbreviated, time: .shortened)) sur \(v.deviceName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Vault sélectionné")
                }
            }
            Section {
                SecureField("Passphrase", text: $passphrase)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Passphrase")
            } footer: {
                Text("Saisis la passphrase qui a servi à sceller ce vault. Elle n'est jamais transmise.")
            }
            Section {
                Button {
                    showConfirmReplace = true
                } label: {
                    Text("Continuer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(passphrase.isEmpty)

                Button("Retour") {
                    step = .list
                    passphrase = ""
                }
            }
        }
    }

    private var confirmSection: some View {
        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Restauration en cours…")
            }
        } footer: {
            Text("Face ID / Touch ID est demandé pour confirmer l'opération. Ta configuration actuelle sera écrasée.")
        }
    }

    private var doneSection: some View {
        Section {
            if let bytes = restoredBytes {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Configuration restaurée", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("Taille : \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Toutes les vues (Fichiers, Transferts…) ont été rafraîchies.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            Button("Terminé") { dismiss() }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Helpers

    private func loadRemotes() async {
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
            if selectedRemote == nil, let first = remotes.first {
                selectedRemote = first
            }
        } catch {
            remotes = []
        }
    }

    private func loadManifest() async {
        do {
            manifest = try await GhostVaultService.shared.listLocalManifest()
        } catch {
            manifest = []
        }
    }

    private func scan(remote: String, folder: String) async {
        loadingScan = true
        defer { loadingScan = false }
        do {
            scanned = try await GhostVaultService.shared.scanRemote(remote: remote, folder: folder)
        } catch {
            scanned = []
            submitError = error.localizedDescription
        }
    }

    private func performRestore() async {
        guard let vault = selectedVault else { return }
        submitError = nil
        step = .confirm
        let bio = await BiometricGate.shared.authenticate(reason: .ghostVaultUnseal)
        guard bio == .authenticated else {
            step = .passphrase
            if case .unavailable(let msg) = bio {
                submitError = msg
            } else if case .userCancelled = bio {
                // OK
            } else {
                submitError = "Authentification annulée."
            }
            return
        }
        submitting = true
        defer {
            submitting = false
            if step == .confirm && submitError == nil {
                step = .passphrase
            }
        }
        do {
            let result = try await GhostVaultService.shared.restore(
                descriptor: vault,
                passphrase: passphrase
            )
            restoredBytes = result.conf.count
            step = .done
        } catch {
            submitError = error.localizedDescription
            step = .passphrase
        }
    }
}

// MARK: - VaultPickerRow

private struct VaultPickerRow: View {
    let descriptor: GhostVaultDescriptor
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? .indigo : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(descriptor.filename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(descriptor.remote) • \(descriptor.remoteCount) remote\(descriptor.remoteCount > 1 ? "s" : "")")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("\(descriptor.deviceName) • \(descriptor.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if descriptor.source == .scanned {
                    Text("distant")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.teal.opacity(0.12), in: Capsule())
                        .foregroundStyle(.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Petit navigateur de dossier (réutilisé depuis CreateVaultView, mais
/// local ici pour éviter de coupler les deux wizards entre eux).
private struct GhostVaultFolderPickerRestore: View {
    let remote: String
    let initial: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String] = []

    var body: some View {
        NavigationStack(path: $pathStack) {
            GhostVaultFolderLevelRestore(remote: remote, path: "", onPick: onPick)
                .navigationTitle("\(remote):")
                .navigationDestination(for: String.self) { p in
                    GhostVaultFolderLevelRestore(remote: remote, path: p, onPick: onPick)
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

private struct GhostVaultFolderLevelRestore: View {
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