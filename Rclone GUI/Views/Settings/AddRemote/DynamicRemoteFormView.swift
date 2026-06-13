//
//  DynamicRemoteFormView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 2: dynamic form generated from `BackendSchema.formFields`.
//  - Required + non-Advanced fields appear at the top in a "Configuration"
//    section.
//  - Advanced fields are tucked behind a DisclosureGroup so the user
//    isn't overwhelmed (s3 has 64 advanced fields, drive has 47).
//  - When a backend exposes a `provider` field (e.g. s3), it is always
//    rendered first because many other fields are conditioned on its
//    value via the `Provider` filter.
//

import SwiftUI

struct DynamicRemoteFormView: View {

    @Bindable var state: WizardState

    let onNext: () -> Void

    @State private var showAdvanced = false

    var body: some View {
        Form {
            if let backend = state.selectedBackend {
                headerSection(for: backend)
                if let guide = BackendOverrides.setupGuides[backend.name] {
                    setupGuideSection(guide)
                }
                if let providerField = providerField(in: backend) {
                    providerSection(field: providerField)
                }
                primarySection(for: backend)
                advancedSection(for: backend)
                if backend.requiresOAuth {
                    oauthHintSection(for: backend)
                }
            } else {
                Section {
                    Label("Aucun backend sélectionné. Reviens à l'étape précédente.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Suivant") { onNext() }
                    .disabled(!state.canProceedFromStep2)
            }
        }
    }

    // MARK: - Sections

    private func headerSection(for backend: BackendSchema) -> some View {
        Section {
            HStack(spacing: 14) {
                AppIconTile(systemImage: backend.icon, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.displayName)
                        .font(.body.weight(.semibold))
                    Text(backend.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func providerSection(field: FieldSpec) -> some View {
        Section {
            FieldRow(
                spec: field,
                value: binding(for: field.name),
                selectedProvider: state.fieldValues["provider"]
            )
        } header: {
            Text("Provider")
        } footer: {
            Text("Le choix du provider détermine quels champs sont disponibles plus bas.")
        }
    }

    private func primarySection(for backend: BackendSchema) -> some View {
        let fields = primaryFields(for: backend)
        return Section {
            if fields.isEmpty {
                Text("Aucun champ obligatoire pour ce backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fields) { field in
                    fieldControl(for: field, backend: backend)
                }
            }
        } header: {
            Text("Configuration")
        }
    }

    @ViewBuilder
    private func advancedSection(for backend: BackendSchema) -> some View {
        let fields = advancedFields(for: backend)
        if !fields.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    ForEach(fields) { field in
                        fieldControl(for: field, backend: backend)
                    }
                } label: {
                    Label("Options avancées (\(fields.count))", systemImage: "gearshape.2")
                }
            }
        }
    }

    private func oauthHintSection(for backend: BackendSchema) -> some View {
        Section {
            Label("Authentification \(backend.displayName) à l'étape suivante.",
                  systemImage: "lock.shield.fill")
                .font(.callout)
                .foregroundStyle(.tint)
        }
    }

    /// Encart « où obtenir tes identifiants » pour les backends à clé/token
    /// sans étape OAuth (pixeldrain, 1Fichier, imagekit, internetarchive,
    /// gofile, sia, storj, netstorage, ulozto…). Purement informatif : il ne
    /// collecte rien, il guide l'utilisateur et nomme les champs à remplir
    /// juste en dessous.
    private func setupGuideSection(_ guide: BackendSetupGuide) -> some View {
        Section {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1).")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                        .frame(width: 22, alignment: .leading)
                    Text(NSLocalizedString(step, comment: "Backend setup step"))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)
            }
            if let url = guide.setupURL {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "safari.fill")
                        Text("Ouvrir la page d'identifiants")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let note = guide.note {
                Label(NSLocalizedString(note, comment: "Backend setup note"),
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("Où obtenir tes identifiants", systemImage: "key.fill")
        }
    }

    // MARK: - Field routing (wrappers get a remote picker)

    /// Wrappers qui référencent UN remote sous-jacent via le champ `remote`.
    /// (crypt est exclu : il a son propre flux guidé CryptSetupView.)
    private static let singleRemoteWrappers: Set<String> = [
        "alias", "cache", "chunker", "compress", "hasher",
    ]
    /// Wrappers qui référencent une LISTE de remotes via le champ `upstreams`.
    private static let listRemoteWrappers: Set<String> = ["union", "combine"]

    /// Rend le bon contrôle pour un champ : picker de remote pour les champs
    /// `remote` / `upstreams` des wrappers (évite de taper « remote:chemin » à
    /// la main), sinon le FieldRow générique.
    @ViewBuilder
    private func fieldControl(for field: FieldSpec, backend: BackendSchema) -> some View {
        if Self.singleRemoteWrappers.contains(backend.name), field.name == "remote" {
            RemoteRefPickerRow(
                label: field.label,
                required: field.required,
                value: binding(for: field.name),
                validationError: validationError(for: field)
            )
        } else if Self.listRemoteWrappers.contains(backend.name), field.name == "upstreams" {
            UpstreamsBuilderRow(
                label: field.label,
                required: field.required,
                isCombine: backend.name == "combine",
                value: binding(for: field.name),
                validationError: validationError(for: field)
            )
        } else {
            FieldRow(
                spec: field,
                value: binding(for: field.name),
                selectedProvider: state.fieldValues["provider"],
                validationError: validationError(for: field)
            )
        }
    }

    // MARK: - Field selection helpers

    private func providerField(in backend: BackendSchema) -> FieldSpec? {
        // Show "provider" first only when it's a real Exclusive picker
        // (= the backend uses sub-providers). Other "provider" strings
        // (rare) stay in the regular flow.
        guard let field = backend.formFields.first(where: { $0.name == "provider" }) else {
            return nil
        }
        return field.exclusive ? field : nil
    }

    private func primaryFields(for backend: BackendSchema) -> [FieldSpec] {
        let providerName = state.fieldValues["provider"]
        return backend.formFields.filter { field in
            // Skip the provider field if we already render it in its own section.
            if let separated = providerField(in: backend), separated.id == field.id {
                return false
            }
            guard !field.advanced else { return false }
            return field.isVisible(for: providerName)
        }
    }

    private func advancedFields(for backend: BackendSchema) -> [FieldSpec] {
        let providerName = state.fieldValues["provider"]
        return backend.formFields.filter { field in
            field.advanced && field.isVisible(for: providerName)
        }
    }

    // MARK: - Bindings & validation

    private func binding(for fieldName: String) -> Binding<String> {
        Binding(
            get: { state.fieldValues[fieldName] ?? "" },
            set: { state.fieldValues[fieldName] = $0 }
        )
    }

    private func validationError(for field: FieldSpec) -> FieldValidationError? {
        let value = state.fieldValues[field.name] ?? ""
        // Don't show "required" until the user has tried to advance —
        // showing it on initial render is just visual noise.
        let error = field.validate(value)
        if error == .required && value.isEmpty { return nil }
        return error
    }
}

// MARK: - Remote reference controls (wrappers)

/// Champ « remote sous-jacent » pour alias/cache/chunker/compress/hasher.
/// Bouton « Choisir un remote… » → feuille (remote + dossier) qui écrit
/// `remote:chemin` dans le champ. Saisie manuelle toujours possible.
private struct RemoteRefPickerRow: View {
    let label: String
    let required: Bool
    @Binding var value: String
    var validationError: FieldValidationError?

    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(.semibold))
                if required {
                    Text("• requis").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Button { showPicker = true } label: {
                HStack {
                    Image(systemName: "externaldrive.fill.badge.plus")
                    if value.isEmpty {
                        Text("Choisir un remote…")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(value)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("Parcourir").font(.callout).foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            TextField("ou saisir « remote:chemin »", text: $value)
                .rgNoAutocap()
                .autocorrectionDisabled()
                .font(.caption)
                .foregroundStyle(.secondary)
            if let validationError {
                Label(validationError.errorDescription ?? "Erreur",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            } else {
                Text("Le remote existant que ce backend va envelopper.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showPicker) {
            RemoteReferenceSheet { picked in value = picked }
        }
    }
}

/// Champ `upstreams` pour union / combine : liste éditable de références, avec
/// ajout via le picker. union → « remote:chemin » ; combine → « nom=remote:chemin ».
private struct UpstreamsBuilderRow: View {
    let label: String
    let required: Bool
    let isCombine: Bool
    @Binding var value: String
    var validationError: FieldValidationError?

    @State private var entries: [String] = []
    @State private var didLoad = false
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(.semibold))
                if required {
                    Text("• requis").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if entries.isEmpty {
                Text("Aucun remote ajouté.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entries.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        TextField("remote:chemin", text: Binding(
                            get: { entries.indices.contains(i) ? entries[i] : "" },
                            set: { if entries.indices.contains(i) { entries[i] = $0; sync() } }
                        ))
                        .rgNoAutocap()
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                        Button {
                            if entries.indices.contains(i) { entries.remove(at: i); sync() }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button { showPicker = true } label: {
                Label("Ajouter un remote", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if let validationError {
                Label(validationError.errorDescription ?? "Erreur",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            } else {
                Text(isCombine
                     ? "Chaque entrée mappe un dossier : « nom=remote:chemin »."
                     : "Remotes fusionnés. Ajoute « :ro » en fin d'entrée pour la lecture seule.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            entries = value.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        }
        .sheet(isPresented: $showPicker) {
            RemoteReferenceSheet { picked in
                if isCombine {
                    let dir = picked.split(separator: ":").first.map(String.init) ?? "dir"
                    entries.append("\(dir)=\(picked)")
                } else {
                    entries.append(picked)
                }
                sync()
            }
        }
    }

    private func sync() {
        value = entries
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Feuille de sélection : liste les remotes existants puis laisse parcourir
/// leurs dossiers. Renvoie une référence `remote:chemin` (ou `remote:` racine).
private struct RemoteReferenceSheet: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                if loading {
                    HStack { ProgressView(); Text("Chargement des remotes…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if remotes.isEmpty {
                    Label("Aucun remote disponible. Crée d'abord un stockage simple (Drive, S3, SFTP…), puis reviens.",
                          systemImage: "externaldrive.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Section("Remotes") {
                        ForEach(remotes) { r in
                            NavigationLink {
                                RemoteRefFolderLevel(remote: r.name, path: "") { picked in
                                    onPick(picked)
                                    dismiss()
                                }
                                .navigationTitle("\(r.name):")
                            } label: {
                                Label("\(r.name) (\(r.type))",
                                      systemImage: r.isCrypt ? "lock.shield.fill" : "externaldrive")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choisir un remote")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Un niveau du browser de dossiers d'un remote, avec « Choisir ce dossier ».
private struct RemoteRefFolderLevel: View {
    let remote: String
    let path: String
    let onPick: (String) -> Void

    @State private var entries: [RemoteEntryDTO] = []
    @State private var loading = true
    @State private var loadError: String?

    private var directories: [RemoteEntryDTO] { entries.filter(\.isDirectory) }
    private var pickValue: String { path.isEmpty ? "\(remote):" : "\(remote):\(path)" }

    var body: some View {
        List {
            Section {
                Button {
                    onPick(pickValue)
                } label: {
                    Label(path.isEmpty ? "Choisir la racine" : "Choisir « \(path) »",
                          systemImage: "checkmark.circle.fill")
                }
            }
            Section("Sous-dossiers") {
                if loading {
                    HStack { ProgressView(); Text("Chargement…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                } else if directories.isEmpty {
                    Text("Aucun sous-dossier ici.").foregroundStyle(.secondary)
                } else {
                    ForEach(directories) { dir in
                        NavigationLink {
                            RemoteRefFolderLevel(remote: remote, path: dir.pathInRemote, onPick: onPick)
                                .navigationTitle(dir.name)
                        } label: {
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
            loadError = error.localizedDescription
        }
    }
}
