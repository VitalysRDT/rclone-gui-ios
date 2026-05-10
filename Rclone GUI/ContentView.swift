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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showOnboarding = false
    @State private var showReviewPrompt = false
    @State private var reviewPromptCheckTask: Task<Void, Never>?

    var body: some View {
        MainTabView()
            .alert("Un avis sur l'App Store ?", isPresented: $showReviewPrompt) {
                Button("Mettre des étoiles") {
                    ReviewPromptService.shared.requestReview()
                }
                Button("Plus tard", role: .cancel) {
                    ReviewPromptService.shared.remindLater()
                }
                Button("Ne plus demander", role: .destructive) {
                    ReviewPromptService.shared.dismissPermanently()
                }
            } message: {
                Text("Je suis un jeune développeur et ton avis m'aide énormément à améliorer Rclone GUI. Si l'app t'est utile, tu peux laisser quelques étoiles sur l'App Store.")
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView(isPresented: Binding(
                    get: { showOnboarding },
                    set: { newValue in
                        showOnboarding = newValue
                        if !newValue { hasCompletedOnboarding = true }
                        scheduleReviewPromptCheck()
                    }
                ))
                .interactiveDismissDisabled(true)
            }
            .task {
                ReviewPromptService.shared.recordLaunchIfNeeded()
                ReviewPromptService.shared.appDidBecomeActive()
                if !hasCompletedOnboarding {
                    showOnboarding = true
                } else {
                    scheduleReviewPromptCheck()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    ReviewPromptService.shared.appDidBecomeActive()
                    scheduleReviewPromptCheck()
                case .inactive, .background:
                    ReviewPromptService.shared.appDidMoveToBackground()
                @unknown default:
                    break
                }
            }
    }

    private func scheduleReviewPromptCheck() {
        // Évite les Tasks empilées : si une vérification est déjà en cours
        // ou si un prompt est déjà affiché, on ne relance rien.
        guard hasCompletedOnboarding, !showOnboarding, !showReviewPrompt else { return }
        guard reviewPromptCheckTask == nil else { return }
        reviewPromptCheckTask = Task { @MainActor in
            defer { reviewPromptCheckTask = nil }
            try? await Task.sleep(for: .seconds(2))
            guard !showReviewPrompt else { return }
            guard ReviewPromptService.shared.shouldShowPrompt(hasCompletedOnboarding: hasCompletedOnboarding) else { return }
            ReviewPromptService.shared.markPromptShown()
            showReviewPrompt = true
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Remote.self, RemoteEntry.self, Transfer.self, TransferBatch.self, PhotoSyncAsset.self],
            inMemory: true
        )
}
