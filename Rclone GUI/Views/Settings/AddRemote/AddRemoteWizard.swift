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
            OAuthView(state: state, onNext: { state.advance() })
        case .recapAndTest:
            RecapAndTestView(state: state, onCreated: handleCreated)
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

#Preview {
    AddRemoteWizard(onSaved: {})
}
