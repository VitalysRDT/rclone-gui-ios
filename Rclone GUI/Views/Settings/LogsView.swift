//
//  LogsView.swift
//  Rclone GUI — Views/Settings
//

import SwiftUI

struct LogsView: View {
    @State private var entries: [LogEntry] = []
    @State private var levelFilter: LogLevel? = nil
    @State private var exportURL: URL?
    @State private var showShare = false
    @State private var exportError: String?
    // Pagination : limite l'affichage initial pour éviter les freezes en
    // scroll quand le ring buffer (1000 entries) est plein. Le bouton
    // "Afficher plus" en débloque 100 supplémentaires à chaque tap.
    @State private var displayLimit: Int = 100
    private static let pageSize = 100

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if entries.isEmpty {
                ContentUnavailableView("Aucun log",
                                       systemImage: "doc.text",
                                       description: Text("Les événements apparaîtront ici dès la première action."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let visibleEntries = Array(entries.prefix(displayLimit))
                List {
                    ForEach(visibleEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.level.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(badgeColor(entry.level), in: .capsule)
                                    .foregroundStyle(.white)
                                Text(entry.category)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 2)
                    }
                    if entries.count > visibleEntries.count {
                        Button {
                            displayLimit += Self.pageSize
                        } label: {
                            HStack {
                                Spacer()
                                Text("Afficher \(min(Self.pageSize, entries.count - visibleEntries.count)) de plus (\(entries.count - visibleEntries.count) restants)")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                        }
                        .foregroundStyle(.tint)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Logs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Tout effacer", role: .destructive) {
                        Task {
                            await LogService.shared.clear()
                            await MainActor.run {
                                FileProviderManager.shared.clearDiagnostics()
                            }
                            await reload()
                        }
                    }
                    Button("Réinitialiser Fichiers") {
                        Task {
                            await FileProviderManager.shared.resetDomain()
                            await reload()
                        }
                    }
                    Button("Rafraîchir") {
                        Task { await reload() }
                    }
                    Button("Exporter") {
                        Task { await exportLogs() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await reload() }
        #if canImport(UIKit)
        .sheet(isPresented: $showShare) {
            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Partager le fichier de log", systemImage: "square.and.arrow.up")
                        .padding()
                }
            }
        }
        #endif
        .alert(
            "Export échoué",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            ),
            presenting: exportError
        ) { _ in
            Button("OK", role: .cancel) { exportError = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var filterBar: some View {
        Picker("Niveau", selection: $levelFilter) {
            Text("Tous").tag(nil as LogLevel?)
            Text("Info").tag(LogLevel.info as LogLevel?)
            Text("Debug").tag(LogLevel.debug as LogLevel?)
            Text("Erreur").tag(LogLevel.error as LogLevel?)
        }
        .pickerStyle(.segmented)
        .padding()
        .onChange(of: levelFilter) { _, _ in
            // Reset la pagination quand on change de filtre, sinon l'utilisateur
            // peut se retrouver avec un filtre vide alors qu'il y avait du contenu
            // pour ce niveau au-delà de la fenêtre actuelle.
            displayLimit = Self.pageSize
            Task { await reload() }
        }
    }

    private func badgeColor(_ level: LogLevel) -> Color {
        switch level {
        case .info:  return .blue
        case .debug: return .gray
        case .error: return .red
        }
    }

    private func reload() async {
        let appEntries = await LogService.shared.entries(filter: levelFilter)
        let providerEntries = await MainActor.run {
            FileProviderManager.shared.diagnosticEntries()
        }
        .filter { entry in
            levelFilter == nil || entry.level == levelFilter
        }
        entries = (appEntries + providerEntries)
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func exportLogs() async {
        do {
            let url = try await LogService.shared.exportAsFile()
            exportURL = url
            showShare = true
        } catch {
            await LogService.shared.log(
                .error,
                category: "logs",
                message: "Export échoué : \(error.localizedDescription)"
            )
            exportError = error.localizedDescription
        }
    }
}
