//
//  RemotesListView.swift
//  Rclone GUI — Views/Remotes
//
//  Top-level screen: lists every remote defined in rclone.conf.
//  Tap a remote → navigate into its root folder.
//

import SwiftUI

struct RemotesListView: View {
    @State private var remotes: [RemoteSummaryDTO] = []
    @State private var loadState: LoadState = .idle
    @State private var isMockEngine = false

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Remotes")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Rafraîchir les remotes")
                    }
                }
                .navigationDestination(for: NavigationDestination.self) { destination in
                    switch destination {
                    case .folder(let remote, let path):
                        FolderView(remote: remote, path: path)
                    }
                }
                .task {
                    if remotes.isEmpty { await load() }
                }
                .refreshable {
                    await load()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle:
            ProgressView("Chargement des remotes…")
        case .loading where remotes.isEmpty:
            ProgressView("Chargement des remotes…")

        case .failed(let message):
            ContentUnavailableView {
                Label("Erreur de chargement", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }

        case .loaded where remotes.isEmpty:
            ContentUnavailableView(
                "Aucun remote",
                systemImage: "externaldrive.connected.to.line.below",
                description: Text("Importe ton rclone.conf depuis Réglages pour commencer.")
            )

        case .loading, .loaded:
            let list = List {
                if isMockEngine {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Mode mock actif").font(.caption.weight(.semibold))
                                Text("Les remotes sont lus depuis ton rclone.conf chiffré, mais la navigation, le téléchargement et le streaming nécessitent le vrai moteur. Build `RcloneKit.xcframework` via `./scripts/build-rclone.sh`.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    ForEach(remotes) { remote in
                        NavigationLink(value: NavigationDestination.folder(remote: remote.name, path: "")) {
                            RemoteRowView(remote: remote)
                        }
                    }
                } header: {
                    Text("\(remotes.count) remote\(remotes.count > 1 ? "s" : "")")
                }
            }
            #if os(iOS)
            list.listStyle(.insetGrouped)
            #else
            list
            #endif
        }
    }

    private func load() async {
        loadState = .loading
        isMockEngine = await RcloneCore.shared.isMockEngine
        do {
            remotes = try await RemoteService.shared.listRemoteSummaries()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }
}

struct RemoteRowView: View {
    let remote: RemoteSummaryDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(remote.name)
                        .font(.body)
                        .lineLimit(1)
                    if remote.isCrypt {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .accessibilityLabel("Remote chiffré")
                    }
                }
                Text(humanType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch remote.type {
        case "s3":          return "externaldrive.fill"
        case "b2":          return "externaldrive.fill.badge.checkmark"
        case "sftp":        return "server.rack"
        case "ftp":         return "server.rack"
        case "webdav":      return "network"
        case "drive":       return "icloud.fill"
        case "dropbox":     return "shippingbox.fill"
        case "onedrive":    return "icloud.fill"
        case "box":         return "shippingbox.fill"
        case "crypt":       return "lock.shield"
        case "alias",
             "union",
             "combine":     return "link.circle.fill"
        case "local":       return "internaldrive.fill"
        default:            return "questionmark.circle"
        }
    }

    private var humanType: String {
        switch remote.type {
        case "s3":          return "S3 / R2 / Bunny / Wasabi"
        case "b2":          return "Backblaze B2"
        case "sftp":        return "SFTP"
        case "ftp":         return "FTP"
        case "webdav":      return "WebDAV"
        case "drive":       return "Google Drive"
        case "dropbox":     return "Dropbox"
        case "onedrive":    return "OneDrive"
        case "box":         return "Box"
        case "crypt":       return "Crypt (chiffré)"
        case "alias":       return "Alias"
        case "union":       return "Union de remotes"
        case "combine":     return "Combine"
        case "local":       return "Local"
        case "unknown":     return "Type inconnu"
        default:            return remote.type
        }
    }

    private var accessibilityText: String {
        let crypt = remote.isCrypt ? ", chiffré" : ""
        return "\(remote.name), \(humanType)\(crypt)"
    }
}

#Preview {
    RemotesListView()
}
