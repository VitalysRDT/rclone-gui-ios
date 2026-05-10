//
//  AddRemoteWizard.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Multi-step wizard that replaces the legacy AddRemoteView. Drives
//  the user through:
//    1. Name + backend selection
//    2. Dynamic form generated from `config/providers`
//    3. OAuth (only for backends that need it)
//    4. Recap + test connection + save
//
//  The wizard owns a single `WizardState` (@Observable) that every
//  step reads and writes. Steps are presented inside a NavigationStack
//  so the system back-button works as expected.
//
//  This file contains the orchestration only — each step is its own
//  View in the Steps subdirectory. P0.4 ships placeholder steps so
//  the skeleton compiles and integrates with existing call sites.
//

import SwiftUI

struct AddRemoteWizard: View {

    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state = WizardState()

    var body: some View {
        NavigationStack {
            currentStepView
                .navigationTitle(navigationTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { handleCancel() }
                    }
                }
        }
        .task { await loadExistingRemoteNames() }
    }

    // MARK: - Step routing

    @ViewBuilder
    private var currentStepView: some View {
        switch state.step {
        case .nameAndBackend:
            NameAndBackendView(state: state, onNext: { state.advance() })
        case .formFields:
            DynamicRemoteFormView(state: state, onNext: { state.advance() })
        case .oauth:
            OAuthStep(state: state)
        case .recapAndTest:
            RecapAndTestStep(state: state, onCreated: handleCreated)
        }
    }

    private var navigationTitle: String {
        switch state.step {
        case .nameAndBackend: return "Nouveau remote"
        case .formFields:     return state.selectedBackend?.displayName ?? "Configuration"
        case .oauth:          return "Authentification"
        case .recapAndTest:   return "Récapitulatif"
        }
    }

    // MARK: - Lifecycle

    private func loadExistingRemoteNames() async {
        do {
            let names = try await RcloneCore.shared.listRemoteNames()
            state.existingRemoteNames = Set(names)
        } catch {
            // Non-fatal — the user will still be blocked by config/create
            // if they pick a duplicate name. Log for diagnostics.
            await LogService.shared.log(
                .error,
                category: "wizard",
                message: "listRemoteNames failed: \(error.localizedDescription)"
            )
        }
    }

    private func handleCancel() {
        // If we already wrote the remote to rclone.conf during the
        // "Tester" step, undo it before dismissing so we don't leave
        // an orphan section behind.
        if state.remoteWasPreCreated, !state.name.isEmpty {
            let nameSnapshot = state.name
            Task.detached {
                struct DeleteInput: Encodable { let name: String }
                let payload = DeleteInput(name: nameSnapshot)
                let json = (try? JSONEncoder().encode(payload))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                _ = try? await RcloneCore.shared.rpcRaw("config/delete", json)
                await LogService.shared.log(
                    .info,
                    category: "wizard",
                    message: "Wizard canceled — cleaned up orphan remote \(nameSnapshot)"
                )
            }
        }
        dismiss()
    }

    private func handleCreated() {
        onSaved()
        dismiss()
    }
}

// MARK: - Step placeholders (Sprint A skeleton)
//
// Each placeholder shows enough context to verify the wiring before
// the full UI lands in Sprint B/C. They share the same minimalist
// layout: a label saying which step we're on, plus a "Suivant"
// button that advances the state machine.

private struct StepPlaceholder: View {
    let title: String
    let state: WizardState
    var canProceed: Bool = true

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
            Text("Skeleton — implémentation Sprint B/C.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack {
                if state.step != .nameAndBackend {
                    Button("Retour") { state.goBack() }
                        .buttonStyle(.bordered)
                }
                Button("Suivant") { state.advance() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canProceed)
            }
        }
        .padding()
    }
}

private struct OAuthStep: View {
    let state: WizardState
    var body: some View {
        StepPlaceholder(title: "Étape 3 — OAuth", state: state)
    }
}

private struct RecapAndTestStep: View {
    let state: WizardState
    let onCreated: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Étape 4 — Récap & Test")
                .font(.title2.bold())
            Text("Skeleton — implémentation Sprint B/C.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Retour") { state.goBack() }
                    .buttonStyle(.bordered)
                Button("Créer") { onCreated() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

#Preview {
    AddRemoteWizard(onSaved: {})
}
