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
    @State private var incomingHandoff: IncomingHandoff?
    @State private var handoffOpenError: String?

    /// Fichier .rclonebackup reçu (AirDrop / Fichiers) dont le payload
    /// HND1: a déjà été extrait — déclenche la sheet « Recevoir ».
    private struct IncomingHandoff: Identifiable {
        let id = UUID()
        let payload: String
    }

    var body: some View {
        SubscriptionGate {
            MainTabView()
        }
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
                    // L'essai gratuit a pu expirer pendant que l'app dormait :
                    // on ré-évalue pour faire apparaître le paywall si besoin.
                    SubscriptionService.shared.refreshOnForeground()
                case .inactive, .background:
                    ReviewPromptService.shared.appDidMoveToBackground()
                @unknown default:
                    break
                }
            }
            .onOpenURL { url in
                handleIncomingFile(url)
            }
            .sheet(item: $incomingHandoff) { incoming in
                NavigationStack {
                    HandoffReceiveView(prefilledPayload: incoming.payload)
                }
            }
            .alert(
                "Impossible d'ouvrir ce fichier",
                isPresented: Binding(
                    get: { handoffOpenError != nil },
                    set: { if !$0 { handoffOpenError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(handoffOpenError ?? "")
            }
    }

    /// Fichier .rclonebackup ouvert depuis l'extérieur (AirDrop,
    /// Fichiers, Mail…) : extrait le payload HND1: et ouvre le wizard
    /// « Handoff P2P — recevoir » directement à l'étape passphrase.
    private func handleIncomingFile(_ url: URL) {
        guard HandoffInbox.isHandoffFile(url) else { return }
        do {
            let payload = try HandoffInbox.extractPayload(fromFileAt: url)
            incomingHandoff = IncomingHandoff(payload: payload)
        } catch {
            handoffOpenError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
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
            for: [Remote.self, RemoteEntry.self, Transfer.self, TransferBatch.self, PhotoSyncAsset.self, TrashEntry.self, SavedLocation.self],
            inMemory: true
        )
}
