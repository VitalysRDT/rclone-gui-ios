//
//  MainTabView.swift
//  Rclone GUI — Views
//
//  Root tab container. Holds the three primary surfaces: Remotes,
//  Transfers, Settings.
//

import SwiftUI

struct MainTabView: View {
    @State private var selection: Tab = .remotes

    enum Tab: Hashable {
        case remotes
        case transfers
        case settings
    }

    var body: some View {
        TabView(selection: $selection) {
            RemotesListView()
                .tabItem {
                    Label("Remotes", systemImage: "externaldrive")
                }
                .tag(Tab.remotes)

            TransfersView()
                .tabItem {
                    Label("Transferts", systemImage: "arrow.up.arrow.down.circle")
                }
                .tag(Tab.transfers)

            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
    }
}

#Preview {
    MainTabView()
}
