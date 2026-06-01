//
//  CryptSetupView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Guided crypt setup. Instead of the generic dynamic form (where the user
//  would have to hand-type `remote = gdrive:folder`), this walks them through:
//    1. Picking the underlying (plaintext) remote that crypt will wrap.
//    2. Browsing that remote to choose the destination folder.
//    3. Setting the encryption password (+ optional salt) and name-encryption.
//
//  Selections are committed into WizardState.fieldValues (via
//  commitCryptFieldValues) on advance, so the recap + config/create steps
//  treat crypt like any other backend. rclone obscures the password at write
//  time (config/create opt.obscure = true, set in RecapAndTestView).
//

import SwiftUI

struct CryptSetupView: View {

    @Bindable var state: WizardState
    let onNext: () -> Void

    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var loadingRemotes = true
    @State private var loadError: String?
    @State private var confirmPassword = ""
    @State private var showFolderPicker = false

    /// Non-crypt remotes only — wrapping a crypt in another crypt is almost
    /// never what the user wants here.
    private var selectableRemotes: [RemoteSummaryDTO] {
        remotes.filter { !$0.isCrypt }
    }

    private var passwordsMatch: Bool {
        confirmPassword == state.cryptPassword
    }

    var body: some View {
        Form {
            underlyingSection
            folderSection
            passwordSection
            encryptionSection
        }
        .task { await loadRemotes() }
        .sheet(isPresented: $showFolderPicker) {
            CryptFolderPicker(
                remote: state.cryptUnderlyingRemote,
                initialPath: state.cryptFolderPath
            ) { picked in
                state.cryptFolderPath = picked
                showFolderPicker = false
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Suivant") { onNext() }
                    .disabled(!state.canProceedFromCrypt || !passwordsMatch)
            }
        }
    }

    // MARK: - Underlying remote

    @ViewBuilder
    private var underlyingSection: some View {
        Section {
            if loadingRemotes {
                HStack {
                    ProgressView()
                    Text("Chargement des remotes…").foregroundStyle(.secondary)
                }
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if selectableRemotes.isEmpty {
                Label("Aucun stockage disponible. Ajoute d'abord un remote (Drive, S3, SFTP…) puis reviens créer le coffre.",
                      systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Stockage", selection: $state.cryptUnderlyingRemote) {
                    Text("Choisir…").tag("")
                    ForEach(selectableRemotes) { remote in
                        Text("\(remote.name) (\(remote.type))").tag(remote.name)
                    }
                }
                .onChange(of: state.cryptUnderlyingRemote) { _, _ in
                    // Le dossier choisi appartenait au remote précédent — on le
                    // réinitialise quand on change de stockage.
                    state.cryptFolderPath = ""
                }
            }
        } header: {
            Text("Stockage sous-jacent")
        } footer: {
            Text("Le coffre chiffre les fichiers au-dessus de ce remote. Les données restent stockées chez le fournisseur, mais chiffrées de bout en bout.")
        }
    }

    // MARK: - Folder

    @ViewBuilder
    private var folderSection: some View {
        Section {
            Button {
                showFolderPicker = true
            } label: {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dossier de destination")
                                .foregroundStyle(.primary)
                            Text(folderDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } icon: {
                        Image(systemName: "folder")
                    }
                    Spacer()
                    Text("Parcourir")
                        .font(.callout)
                        .foregroundStyle(RG.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(state.cryptUnderlyingRemote.isEmpty)
        } header: {
            Text("Dossier")
        } footer: {
            Text("Emplacement du coffre dans le remote. Laisse à la racine pour chiffrer tout le remote.")
        }
    }

    private var folderDisplay: String {
        guard !state.cryptUnderlyingRemote.isEmpty else {
            return String(localized: "Sélectionne d'abord un stockage")
        }
        return state.cryptRemoteValue
    }

    // MARK: - Password

    @ViewBuilder
    private var passwordSection: some View {
        Section {
            SecureField("Mot de passe", text: $state.cryptPassword)
            SecureField("Confirmer le mot de passe", text: $confirmPassword)
            if !confirmPassword.isEmpty && !passwordsMatch {
                Label("Les mots de passe ne correspondent pas.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            SecureField("Sel / password2 (optionnel)", text: $state.cryptPassword2)
        } header: {
            Text("Mot de passe")
        } footer: {
            Text("Sans ce mot de passe, les fichiers sont irrécupérables — il n'est stocké que sur ton appareil. Le sel (password2) renforce le chiffrement ; conserve-le aussi.")
        }
    }

    // MARK: - Encryption options

    @ViewBuilder
    private var encryptionSection: some View {
        Section {
            Picker("Noms de fichiers", selection: $state.cryptFilenameEncryption) {
                Text("Chiffrés (standard)").tag("standard")
                Text("Masqués (obfuscate)").tag("obfuscate")
                Text("En clair (off)").tag("off")
            }
            Toggle("Chiffrer les noms de dossiers", isOn: $state.cryptDirNameEncryption)
        } header: {
            Text("Chiffrement des noms")
        } footer: {
            Text("« Standard » chiffre noms de fichiers et dossiers. « En clair » garde les noms lisibles (utile pour retrouver des fichiers côté fournisseur).")
        }
    }

    // MARK: - Loading

    private func loadRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Folder picker

/// Lightweight directory browser used to pick the crypt destination folder
/// inside the underlying remote. Navigates with a path stack; each level lists
/// only sub-folders and offers a "use this folder" action.
private struct CryptFolderPicker: View {
    let remote: String
    let initialPath: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            CryptFolderLevel(remote: remote, path: "", onPick: pick)
                .navigationTitle("\(remote):")
                .navigationDestination(for: String.self) { p in
                    CryptFolderLevel(remote: remote, path: p, onPick: pick)
                        .navigationTitle(displayName(p))
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func pick(_ folder: String) {
        onPick(folder)
        dismiss()
    }

    private func displayName(_ p: String) -> String {
        (p as NSString).lastPathComponent
    }
}

private struct CryptFolderLevel: View {
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
                        .font(.caption)
                        .foregroundStyle(.red)
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
