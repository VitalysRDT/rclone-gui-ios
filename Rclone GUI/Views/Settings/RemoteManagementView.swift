//
//  RemoteManagementView.swift
//  Rclone GUI — Views/Settings
//
//  Read-only catalogue of configured remotes with edit / reauthorization
//  actions. The edit action reuses AddRemoteWizard and rclone config/update.
//

import SwiftUI

struct RemoteManagementView: View {
    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var editingRemote: RemoteSummaryDTO?
    @State private var remoteToDelete: RemoteSummaryDTO?
    @State private var actionError: String?

    var body: some View {
        Group {
            if isLoading && remotes.isEmpty {
                ProgressView("Chargement des remotes…")
            } else if let loadError, remotes.isEmpty {
                ContentUnavailableView(
                    "Remotes indisponibles",
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text(loadError)
                )
            } else if remotes.isEmpty {
                ContentUnavailableView(
                    "Aucun remote",
                    systemImage: "externaldrive",
                    description: Text("Ajoute ou importe un remote depuis Réglages.")
                )
            } else {
                List {
                    Section {
                        ForEach(remotes) { remote in
                            remoteRow(remote)
                        }
                    } footer: {
                        Text("Les tokens et mots de passe existants restent masqués. Laisse un champ sensible vide pour le conserver, ou saisis une nouvelle valeur pour le remplacer.")
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Gérer les remotes")
        .task { await load() }
        .sheet(item: $editingRemote) { remote in
            AddRemoteWizard(editingRemoteName: remote.name) {
                editingRemote = nil
                Task { await load() }
            }
        }
        .confirmationDialog(
            "Supprimer ce remote ?",
            isPresented: Binding(
                get: { remoteToDelete != nil },
                set: { if !$0 { remoteToDelete = nil } }
            ),
            presenting: remoteToDelete
        ) { remote in
            Button("Supprimer « \(remote.name) »", role: .destructive) {
                Task { await delete(remote) }
            }
            Button("Annuler", role: .cancel) {}
        } message: { remote in
            Text("Cette action retire uniquement la section de rclone.conf. Les fichiers distants ne sont pas supprimés.")
        }
        .alert(
            "Action impossible",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            ),
            presenting: actionError
        ) { _ in
            Button("OK", role: .cancel) { actionError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func remoteRow(_ remote: RemoteSummaryDTO) -> some View {
        HStack(spacing: 12) {
            Image(systemName: remote.isCrypt ? "lock.shield.fill" : "externaldrive.fill")
                .foregroundStyle(remote.isCrypt ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(remote.name)
                    .font(.body.weight(.semibold))
                Text(remote.type)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                editingRemote = remote
            } label: {
                Label(
                    BackendOverrides.oauthConfigs[remote.type] == nil ? "Modifier" : "Modifier / réautoriser",
                    systemImage: BackendOverrides.oauthConfigs[remote.type] == nil ? "pencil" : "key.fill"
                )
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(
                BackendOverrides.oauthConfigs[remote.type] == nil ? "Modifier \(remote.name)" : "Modifier ou réautoriser \(remote.name)"
            )
            .accessibilityHint("Les valeurs sensibles existantes restent masquées")
            .contextMenu {
                Button {
                    editingRemote = remote
                } label: {
                    Label("Modifier / réautoriser", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    remoteToDelete = remote
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                remoteToDelete = remote
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func delete(_ remote: RemoteSummaryDTO) async {
        remoteToDelete = nil
        do {
            try await RcloneConfigEditor.deleteRemote(name: remote.name)
            await load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        RemoteManagementView()
    }
}
