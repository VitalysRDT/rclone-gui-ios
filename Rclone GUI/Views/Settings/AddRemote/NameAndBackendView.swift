//
//  NameAndBackendView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 1 of AddRemoteWizard: name + backend selection. Loads the
//  catalog asynchronously, surfaces it as collapsible category
//  sections, and exposes a global search for impatient users.
//

import SwiftUI

struct NameAndBackendView: View {

    @Bindable var state: WizardState

    let onNext: () -> Void

    // MARK: - Loading state

    @State private var catalog: [BackendSchema] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            nameSection
            if state.nameIsValid && !state.nameAlreadyExists {
                searchSection
                if isLoading {
                    loadingSection
                } else if let loadError {
                    errorSection(loadError)
                } else if filteredCatalog.isEmpty {
                    emptySearchSection
                } else if !state.searchQuery.isEmpty {
                    resultsSection
                } else {
                    categorySections
                }
                advancedSection
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.nameIsValid && !state.nameAlreadyExists)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Suivant") {
                    state.useInteractiveCLI = false
                    onNext()
                }
                .disabled(!state.canProceedFromStep1)
            }
        }
        .task { await loadCatalog() }
        .onAppear { nameFocused = true }
    }

    private var advancedSection: some View {
        Section {
            Button {
                state.useInteractiveCLI = true
                onNext()
            } label: {
                HStack {
                    Image(systemName: "terminal")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mode interactif (CLI)")
                            .font(.subheadline.weight(.semibold))
                        Text("Réplique `rclone config` — utile pour crypt, alias, union, combine et tout backend exigeant des prompts dynamiques.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .disabled(!state.canProceedFromStep1)
        } header: {
            Text("Configuration avancée")
        } footer: {
            Text("Le mode interactif est compatible avec 100 % des backends rclone, y compris ceux non listés dans le catalogue graphique.")
                .font(.caption2)
        }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            // Label masqué (l'en-tête de section dit déjà « Nom du remote ») et
            // exemple en prompt → s'affiche comme placeholder dans le champ sur
            // iOS comme sur macOS (sinon le titre devient un libellé à gauche).
            TextField("Nom du remote", text: $state.name, prompt: Text("ex : mondrive"))
                .labelsHidden()
                .rgNoAutocap()
                .autocorrectionDisabled()
                .focused($nameFocused)
                .submitLabel(.next)
                .onSubmit { nameFocused = false }
            if state.nameAlreadyExists {
                Label("Un remote « \(state.name) » existe déjà.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !state.name.isEmpty && !state.nameIsValid {
                Label("Caractères interdits : « : », « [ », « ] », « / »",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Nom du remote")
        } footer: {
            if !state.nameIsValid || state.nameAlreadyExists {
                Text("Donne d'abord un nom à ton remote pour afficher la liste des connexions disponibles.")
                    .font(.caption2)
            }
        }
    }

    private var searchSection: some View {
        Section {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Recherche backend", text: $state.searchQuery, prompt: Text("Rechercher (drive, S3, sftp…)"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .rgNoAutocap()
                    .autocorrectionDisabled()
                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingSection: some View {
        Section {
            HStack {
                ProgressView()
                Text("Chargement des backends rclone…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Catalogue indisponible", systemImage: "wifi.exclamationmark")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Réessayer") {
                    Task { await loadCatalog(forcingReload: true) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var emptySearchSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Aucun backend ne correspond à « \(state.searchQuery) ».")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Effacer la recherche") {
                    state.searchQuery = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
    }

    private var resultsSection: some View {
        Section("Résultats (\(filteredCatalog.count))") {
            ForEach(filteredCatalog) { backend in
                rowButton(for: backend)
            }
        }
    }

    private var categorySections: some View {
        ForEach(orderedCategories, id: \.id) { category in
            let bucket = catalog.filter { $0.category == category }
            if !bucket.isEmpty {
                Section {
                    ForEach(bucket) { backend in
                        rowButton(for: backend)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: category.icon)
                        Text(category.displayName.uppercased())
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
    }

    private func rowButton(for backend: BackendSchema) -> some View {
        Button {
            state.selectedBackend = backend
            // The backend list is only rendered when the name is valid,
            // so tapping any row can directly advance the wizard.
            nameFocused = false
            state.useInteractiveCLI = false
            onNext()
        } label: {
            BackendListRow(
                backend: backend,
                isSelected: state.selectedBackend?.name == backend.name
            )
        }
        .buttonStyle(.plain)
        .listRowBackground(
            state.selectedBackend?.name == backend.name
                ? Color.accentColor.opacity(0.12)
                : nil
        )
    }

    // MARK: - Derived

    private var orderedCategories: [BackendCategory] {
        BackendCategory.allCases.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var filteredCatalog: [BackendSchema] {
        let query = state.searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return catalog }
        return catalog.filter { backend in
            backend.name.lowercased().contains(query)
                || backend.displayName.lowercased().contains(query)
                || backend.description.lowercased().contains(query)
        }
    }

    // MARK: - Actions

    private func loadCatalog(forcingReload: Bool = false) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        if forcingReload {
            await RemoteCatalogService.shared.invalidate()
        }
        do {
            catalog = try await RemoteCatalogService.shared.loadCatalog()
        } catch {
            loadError = error.localizedDescription
            await LogService.shared.log(
                .error,
                category: "wizard",
                message: "Catalog load failed: \(error.localizedDescription)"
            )
        }
    }
}
