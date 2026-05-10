//
//  PhotoSyncSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Controls opportunistic Photo Library backup to a selected rclone remote.
//

import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PhotoSyncSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var remotes: [String] = []
    @State private var enabled = false
    @State private var selectedRemote = ""
    @State private var folder = "Phototheque"
    @State private var requiresPower = true
    @State private var allowsCellular = false
    @State private var isSyncing = false
    @State private var message: String?
    @State private var stats = PhotoSyncStats()
    @State private var recentAssets: [PhotoSyncAsset] = []
    @State private var selectedAlbumCount = 0

    @AppStorage("photosync.notificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        Form {
            Section {
                Toggle("Activer la synchro Photos", isOn: $enabled)
                Picker("Remote", selection: $selectedRemote) {
                    Text("Choisir…").tag("")
                    if !selectedRemote.isEmpty && !remotes.contains(selectedRemote) {
                        Text("\(selectedRemote) (configuré)").tag(selectedRemote)
                    }
                    ForEach(remotes, id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }
                TextField("Dossier distant", text: $folder)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } footer: {
                Text("Backup iPhone vers rclone uniquement. Les originaux HEIC/MOV sont conservés, aucune suppression locale automatique.")
            }

            Section {
                Toggle("Exiger la charge", isOn: $requiresPower)
                Toggle("Autoriser le cellulaire", isOn: $allowsCellular)
            } header: {
                Text("Politique")
            } footer: {
                Text("Par défaut, les gros uploads attendent Wi-Fi + charge. iOS décide quand les tâches arrière-plan peuvent reprendre.")
            }

            #if os(iOS)
            Section {
                NavigationLink {
                    PhotoSyncAlbumPicker()
                } label: {
                    HStack {
                        Text("Albums à sauvegarder")
                        Spacer()
                        Text(selectedAlbumCount == 0 ? "Tous" : "\(selectedAlbumCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Notifications après sync", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue { Task { await PhotoSyncService.shared.requestNotificationAuthorization() } }
                    }
            } header: {
                Text("Filtres et notifications")
            } footer: {
                Text("Sans album sélectionné, toutes les photos visibles sont sauvegardées. Une notification locale signalera la fin de chaque cycle de sync si vous l'autorisez.")
            }
            #endif

            Section {
                Button {
                    save()
                    Task { await syncNow() }
                } label: {
                    if isSyncing {
                        HStack {
                            ProgressView()
                            Text("Synchronisation…")
                        }
                    } else {
                        Label("Synchroniser maintenant", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(selectedRemote.isEmpty || isSyncing)

                Button("Enregistrer la configuration") {
                    save()
                }
                .disabled(selectedRemote.isEmpty && enabled)
            } footer: {
                if let message {
                    Text(message)
                }
            }

            if stats.authorization == .limited || stats.authorization == .denied || stats.authorization == .restricted {
                Section {
                    Label(authorizationTitle, systemImage: authorizationIcon)
                        .foregroundStyle(authorizationTint)
                    #if os(iOS)
                    Button("Modifier l'acces Photos") {
                        openPhotoSettings()
                    }
                    #endif
                } footer: {
                    Text(authorizationFooter)
                }
            }

            Section {
                LabeledContent("Photos visibles", value: "\(stats.visible)")
                LabeledContent("Indexés", value: "\(stats.indexed)")
                LabeledContent("En attente", value: "\(stats.pending)")
                LabeledContent("En cours/en file", value: "\(stats.active)")
                LabeledContent("Terminés", value: "\(stats.completed)")
                LabeledContent("Échecs", value: "\(stats.failed)")
            } header: {
                Text("Etat")
            }

            if !recentAssets.isEmpty {
                Section {
                    ForEach(recentAssets) { asset in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(asset.mediaType.capitalized)
                                    .font(.body.weight(.medium))
                                Spacer()
                                AppStatusBadge(title: statusLabel(asset.status), tint: statusColor(asset.status))
                            }
                            Text(asset.localIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let error = asset.lastError, asset.status == .failed {
                                Text(error)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Historique récent")
                }
            }
        }
        .navigationTitle("Synchro Photos")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await load()
            await reloadStats()
            #if os(iOS)
            selectedAlbumCount = PhotoSyncAlbumStore.load().count
            #endif
        }
        .onAppear {
            // Refresh count when returning from the album picker.
            #if os(iOS)
            selectedAlbumCount = PhotoSyncAlbumStore.load().count
            #endif
        }
    }

    private func load() async {
        let service = PhotoSyncService.shared
        enabled = service.isEnabled
        selectedRemote = service.configuredRemote ?? ""
        folder = service.configuredFolder
        requiresPower = service.requiresExternalPower
        allowsCellular = service.allowsCellular
        let loadedRemotes = (try? await RemoteService.shared.listRemoteNames()) ?? []
        if !selectedRemote.isEmpty && !loadedRemotes.contains(selectedRemote) {
            remotes = [selectedRemote] + loadedRemotes
        } else {
            remotes = loadedRemotes
        }
    }

    private func save() {
        PhotoSyncService.shared.configure(
            enabled: enabled,
            remote: selectedRemote.isEmpty ? nil : selectedRemote,
            folder: folder,
            requiresPower: requiresPower,
            allowsCellular: allowsCellular
        )
        message = "Configuration enregistrée."
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        let summary = await PhotoSyncService.shared.startFullSync()
        applySummary(summary)
        reloadRecentAssets()
        if summary.isLimitedAccess {
            message = "Synchro lancée pour les \(summary.visibleAssetCount) photos autorisées. L'accès Photos est limité."
        } else {
            message = "Synchro complète lancée. \(summary.enqueuedCount) ajoutés à la file, \(summary.pendingCount) en attente."
        }
    }

    private func reloadStats() async {
        let summary = await PhotoSyncService.shared.currentSummary()
        applySummary(summary)
        reloadRecentAssets()
    }

    private func applySummary(_ summary: PhotoSyncRunSummary) {
        stats = PhotoSyncStats(
            authorization: summary.authorization,
            visible: summary.visibleAssetCount,
            indexed: summary.indexedCount,
            pending: summary.pendingCount,
            active: summary.activeCount,
            completed: summary.completedCount,
            failed: summary.failedCount
        )
    }

    private func reloadRecentAssets() {
        var descriptor = FetchDescriptor<PhotoSyncAsset>(
            sortBy: [SortDescriptor(\.discoveredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        recentAssets = (try? modelContext.fetch(descriptor)) ?? []
    }

    private var authorizationTitle: String {
        switch stats.authorization {
        case .limited:
            return "Acces Photos limité"
        case .denied, .restricted:
            return "Acces Photos indisponible"
        case .authorized, .notDetermined, .unknown:
            return "Acces Photos"
        }
    }

    private var authorizationFooter: String {
        switch stats.authorization {
        case .limited:
            return "iOS ne donne acces qu'a la selection actuelle. Les autres photos ne peuvent pas etre indexees ni synchronisees."
        case .denied, .restricted:
            return "Autorisez l'acces Photos dans Reglages pour synchroniser la phototheque."
        case .authorized, .notDetermined, .unknown:
            return ""
        }
    }

    private var authorizationIcon: String {
        stats.authorization == .limited ? "photo.badge.exclamationmark" : "lock.slash"
    }

    private var authorizationTint: Color {
        stats.authorization == .limited ? .orange : .red
    }

    #if os(iOS)
    private func openPhotoSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
    #endif

    private func statusLabel(_ status: PhotoSyncStatus) -> String {
        switch status {
        case .pending: return "Attente"
        case .exporting: return "Export"
        case .enqueued: return "En file"
        case .completed: return "Terminé"
        case .failed: return "Échec"
        case .skipped: return "Ignoré"
        }
    }

    private func statusColor(_ status: PhotoSyncStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .exporting: return .orange
        case .enqueued: return .blue
        case .completed: return .green
        case .failed: return .red
        case .skipped: return .gray
        }
    }
}

private struct PhotoSyncStats {
    var authorization = PhotoSyncAuthorizationState.notDetermined
    var visible = 0
    var indexed = 0
    var pending = 0
    var active = 0
    var completed = 0
    var failed = 0
}
