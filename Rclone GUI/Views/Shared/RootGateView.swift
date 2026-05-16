//
//  RootGateView.swift
//  Rclone GUI — Views/Shared
//
//  App-level Face ID gate. Wraps the real root (ContentView) and presents
//  LockedView when biometrics are required and haven't been satisfied yet.
//
//  Two triggers re-lock the app :
//   1. Cold launch when `security.requireBiometricsAtLaunch` is true.
//   2. Returning from background after more than `security.inactivityWipeMinutes`
//      minutes. The cutoff is in-memory only — a cold launch always resets it.
//

import SwiftUI

struct RootGateView<Content: View>: View {
    @AppStorage("security.requireBiometricsAtLaunch") private var requireBiometrics: Bool = true
    @AppStorage("security.inactivityWipeMinutes") private var inactivityWipeMinutes: Int = 30

    @Environment(\.scenePhase) private var scenePhase

    @State private var unlocked: Bool
    @State private var authInFlight = false
    @State private var lastBackgroundedAt: Date?

    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        // Pre-read the toggle so the first frame is the lock screen — avoid
        // flashing ContentView between init and the first body evaluation.
        let required = UserDefaults.standard.object(forKey: "security.requireBiometricsAtLaunch") as? Bool ?? true
        self._unlocked = State(initialValue: !required)
        self.content = content
    }

    var body: some View {
        ZStack {
            content()
                .opacity(shouldShowLockScreen ? 0 : 1)
                .accessibilityHidden(shouldShowLockScreen)
            if shouldShowLockScreen {
                LockedView(
                    onAuthenticate: { Task { await authenticate() } }
                )
                .transition(.opacity)
                .task { await authenticate() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowLockScreen)
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
    }

    private var shouldShowLockScreen: Bool {
        requireBiometrics && !unlocked
    }

    private func authenticate() async {
        guard !authInFlight, shouldShowLockScreen else { return }
        authInFlight = true
        defer { authInFlight = false }
        let result = await BiometricGate.shared.authenticate(reason: .appOpen)
        switch result {
        case .authenticated, .fallback:
            unlocked = true
            lastBackgroundedAt = nil
        case .userCancelled, .unavailable:
            // Reste verrouillé. L'utilisateur peut retaper sur la tuile pour
            // relancer le prompt.
            break
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            // Mémorise le moment de mise en arrière-plan une seule fois par
            // transition (inactive arrive avant background sur iOS — on évite
            // de réécrire la date).
            if requireBiometrics, lastBackgroundedAt == nil {
                lastBackgroundedAt = Date()
            }
        case .active:
            guard requireBiometrics else { return }
            if let last = lastBackgroundedAt {
                let threshold = max(0, inactivityWipeMinutes) * 60
                let elapsed = Date().timeIntervalSince(last)
                if threshold > 0, elapsed >= TimeInterval(threshold) {
                    unlocked = false
                }
                lastBackgroundedAt = nil
            }
        @unknown default:
            break
        }
    }
}
