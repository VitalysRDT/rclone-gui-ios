//
//  MainTabView.swift
//  Rclone GUI — Views
//
//  Root tab container. Holds the four primary surfaces: Home,
//  Files, Transfers, Settings.
//

import SwiftUI

struct MainTabView: View {
    @State private var selection: Tab = .home

    enum Tab: Hashable {
        case home
        case files
        case transfers
        case settings
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView()
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
                .tabItem {
                    Label("Accueil", systemImage: "house")
                }
                .tag(Tab.home)

            NavigationStack {
                FilesRootView()
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
                .tabItem {
                    Label("Fichiers", systemImage: "folder")
                }
                .tag(Tab.files)

            NavigationStack {
                TransfersView()
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
                .tabItem {
                    Label("Transferts", systemImage: "arrow.up.arrow.down.circle")
                }
                .tag(Tab.transfers)

            NavigationStack {
                SettingsView()
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
                .tabItem {
                    Label("Réglages", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }

    @ViewBuilder
    private func navigationDestination(_ destination: NavigationDestination) -> some View {
        switch destination {
        case .folder(let remote, let path):
            FolderView(remote: remote, path: path)
        }
    }
}

#Preview {
    MainTabView()
}
