//
//  SettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Top-level settings screen. Branches to specialized sub-views.
//

import SwiftUI

struct SettingsView: View {
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    Button {
                        showImport = true
                    } label: {
                        Label("Importer un rclone.conf", systemImage: "square.and.arrow.down")
                    }

                    NavigationLink {
                        SecuritySettingsView()
                    } label: {
                        Label("Sécurité & biométrie", systemImage: "lock.shield")
                    }
                }

                Section("Stockage") {
                    NavigationLink {
                        CacheSettingsView()
                    } label: {
                        Label("Cache média", systemImage: "tray.full")
                    }
                }

                Section("Diagnostic") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("À propos", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Réglages")
            .sheet(isPresented: $showImport) {
                ImportConfigView(onImported: {
                    showImport = false
                })
            }
        }
    }
}
