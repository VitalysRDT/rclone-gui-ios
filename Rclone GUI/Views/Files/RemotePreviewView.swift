//
//  RemotePreviewView.swift
//  Rclone GUI — Views/Files
//
//  In-app Quick Look preview for non-media files.
//

import QuickLook
import SwiftUI

#if canImport(UIKit)
import UIKit

struct RemotePreviewHost: View {
    let remote: String
    let entry: RemoteEntryDTO

    @State private var localURL: URL?
    @State private var isPreparingPreview = false
    @State private var error: String?
    @State private var showingActivity = false
    @State private var showingQuickLook = false
    @State private var isInsideCrypt = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FileDetailView(
                entry: entry,
                remote: remote,
                isInsideCrypt: isInsideCrypt,
                onPlay: { Task { await openQuickLook() } },
                onDownload: { Task { await openQuickLook() } },
                onShare: { Task { await prepareThenShare() } },
                onPin: nil
            )
            .navigationTitle(entry.name)
            .rgInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isPreparingPreview {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await prepareThenShare() }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Ouvrir dans une autre app")
                    }
                }
            }
            .overlay {
                if let error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
                    .padding()
                }
            }
        }
        .task { await detectCrypt() }
        .sheet(isPresented: $showingQuickLook) {
            if let localURL {
                NavigationStack {
                    QuickLookPreview(url: localURL)
                        .ignoresSafeArea()
                        .navigationTitle(entry.name)
                        .rgInlineNavTitle()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("OK") { showingQuickLook = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingActivity) {
            if let localURL {
                ActivityView(activityItems: [localURL])
            }
        }
    }

    private func openQuickLook() async {
        await prepareIfNeeded()
        if localURL != nil { showingQuickLook = true }
    }

    private func prepareThenShare() async {
        await prepareIfNeeded()
        if localURL != nil { showingActivity = true }
    }

    private func prepareIfNeeded() async {
        guard localURL == nil, !isPreparingPreview else { return }
        isPreparingPreview = true
        defer { isPreparingPreview = false }
        do {
            localURL = try await MediaCacheService.shared.localPlayableURL(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size,
                policy: .reuseIfCached
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func detectCrypt() async {
        guard let summaries = try? await RemoteService.shared.listRemoteSummaries() else { return }
        if let s = summaries.first(where: { $0.name == remote }) {
            isInsideCrypt = (s.type == "crypt")
        }
    }
}

struct RemoteExternalOpenHost: View {
    let remote: String
    let entry: RemoteEntryDTO

    @State private var localURL: URL?
    @State private var isLoading = true
    @State private var error: String?
    @State private var showingActivity = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Préparation du fichier…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let localURL {
                    ContentUnavailableView {
                        Label("Fichier prêt", systemImage: "doc.badge.arrow.up")
                    } description: {
                        Text(localURL.lastPathComponent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } actions: {
                        Button {
                            showingActivity = true
                        } label: {
                            Label("Ouvrir ou partager", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView {
                        Label("Ouverture impossible", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error ?? "Le fichier n'a pas pu être préparé.")
                    }
                }
            }
            .navigationTitle(entry.name)
            .rgInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingActivity = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Ouvrir dans une autre app")
                    .disabled(localURL == nil)
                }
            }
        }
        .task { await prepare() }
        .sheet(isPresented: $showingActivity) {
            if let localURL {
                ActivityView(activityItems: [localURL])
            }
        }
    }

    private func prepare() async {
        isLoading = true
        defer { isLoading = false }
        do {
            localURL = try await MediaCacheService.shared.localPlayableURL(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size,
                policy: .reuseIfCached
            )
            showingActivity = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif canImport(AppKit)
import AppKit

// macOS : on prépare le fichier localement (même pipeline MediaCacheService que
// sur iOS) puis on délègue à Finder / l'app par défaut via NSWorkspace.
// QuickLook in-window (QLPreviewView) est une amélioration prévue en P4.
private struct MacFilePreparationHost: View {
    let remote: String
    let entry: RemoteEntryDTO
    let title: String

    @State private var localURL: URL?
    @State private var isLoading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Préparation du fichier…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let localURL {
                    ContentUnavailableView {
                        Label("Fichier prêt", systemImage: "doc.badge.arrow.up")
                    } description: {
                        Text(localURL.lastPathComponent)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    } actions: {
                        Button {
                            NSWorkspace.shared.open(localURL)
                        } label: {
                            Label("Ouvrir", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([localURL])
                        } label: {
                            Label("Afficher dans le Finder", systemImage: "folder")
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Aperçu impossible", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error ?? "Le fichier n'a pas pu être préparé.")
                    }
                }
            }
            .navigationTitle(entry.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        isLoading = true
        defer { isLoading = false }
        do {
            localURL = try await MediaCacheService.shared.localPlayableURL(
                remote: remote,
                path: entry.pathInRemote,
                sizeHint: entry.size,
                policy: .reuseIfCached
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct RemotePreviewHost: View {
    let remote: String
    let entry: RemoteEntryDTO
    var body: some View {
        MacFilePreparationHost(remote: remote, entry: entry, title: entry.name)
    }
}

struct RemoteExternalOpenHost: View {
    let remote: String
    let entry: RemoteEntryDTO
    var body: some View {
        MacFilePreparationHost(remote: remote, entry: entry, title: entry.name)
    }
}
#else
struct RemotePreviewHost: View {
    let remote: String
    let entry: RemoteEntryDTO
    var body: some View { Text("Aperçu indisponible") }
}

struct RemoteExternalOpenHost: View {
    let remote: String
    let entry: RemoteEntryDTO
    var body: some View { Text("Ouverture externe indisponible") }
}
#endif
