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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false

    var body: some View {
        MainTabView()
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: Binding(
                    get: { showOnboarding },
                    set: { newValue in
                        showOnboarding = newValue
                        if !newValue { hasCompletedOnboarding = true }
                    }
                ))
                .interactiveDismissDisabled(true)
            }
            .task {
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Remote.self, RemoteEntry.self, Transfer.self], inMemory: true)
}
