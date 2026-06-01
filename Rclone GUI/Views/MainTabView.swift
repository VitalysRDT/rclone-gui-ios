//
//  MainTabView.swift
//  Rclone GUI — Views
//
//  Root container for the four primary surfaces: Home, Files, Transfers,
//  Settings. iOS uses a bottom TabView; macOS uses a native NavigationSplitView
//  sidebar (the iOS floating tab bar looks out of place in a Mac window).
//

import SwiftUI

struct MainTabView: View {
    @State private var selection: Tab = .home

    enum Tab: Hashable, CaseIterable, Identifiable {
        case home
        case files
        case transfers
        case settings

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .home: return "Accueil"
            case .files: return "Fichiers"
            case .transfers: return "Transferts"
            case .settings: return "Réglages"
            }
        }

        var systemImage: String {
            switch self {
            case .home: return "house"
            case .files: return "folder"
            case .transfers: return "arrow.up.arrow.down.circle"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
            .navigationTitle("Rclone GUI")
        } detail: {
            NavigationStack {
                detailView(for: selection)
                    .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
            }
            // Reset the navigation stack when switching sections so a folder
            // pushed under Files doesn't bleed into Home/Transfers/Settings.
            .id(selection)
        }
        #else
        TabView(selection: $selection) {
            ForEach(Tab.allCases) { tab in
                NavigationStack {
                    detailView(for: tab)
                        .navigationDestination(for: NavigationDestination.self, destination: navigationDestination)
                }
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .tag(tab)
            }
        }
        #endif
    }

    @ViewBuilder
    private func detailView(for tab: Tab) -> some View {
        switch tab {
        case .home: HomeView()
        case .files: FilesRootView()
        case .transfers: TransfersView()
        case .settings: SettingsView()
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
