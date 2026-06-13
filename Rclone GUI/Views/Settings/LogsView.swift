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

    // Rapport de crash de la session précédente (capturé par CrashReporter).
    @State private var crashReport: String?
    @State private var crashReportURL: URL?
    @State private var showCrashReport = false

    var body: some View {
        VStack(spacing: 0) {
            if crashReport != nil {
                crashBanner
                Divider()
            }
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
        .rgInlineNavTitle()
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
        .task {
            await reload()
            crashReport = CrashReporter.pendingReportText()
            crashReportURL = CrashReporter.pendingReportFileURL()
        }
        #if canImport(UIKit)
        .sheet(isPresented: $showCrashReport) {
            NavigationStack {
                ScrollView {
                    Text(crashReport ?? "")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Rapport de crash")
                .rgInlineNavTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        if let url = crashReportURL {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { showCrashReport = false }
                    }
                }
            }
        }
        #endif
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

    @ViewBuilder
    private var crashBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Crash détecté", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("L'app a quitté inopinément lors de la session précédente. Envoie le rapport au développeur pour aider à corriger le problème.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    showCrashReport = true
                } label: {
                    Label("Voir le rapport", systemImage: "doc.text.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                #if canImport(UIKit)
                if let url = crashReportURL {
                    ShareLink(item: url) {
                        Label("Envoyer", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                #endif

                Spacer(minLength: 0)

                Button("Ignorer") {
                    CrashReporter.clearPendingReport()
                    crashReport = nil
                    crashReportURL = nil
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
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
