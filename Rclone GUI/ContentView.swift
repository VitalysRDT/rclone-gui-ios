//
//  ContentView.swift
//  Rclone GUI
//
//  Phase B entry point: shows the remotes list. Future phases plug
//  in a sidebar (settings, transfers) on iPad / macOS via a
//  NavigationSplitView.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        RemotesListView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Remote.self, RemoteEntry.self, Transfer.self], inMemory: true)
}
