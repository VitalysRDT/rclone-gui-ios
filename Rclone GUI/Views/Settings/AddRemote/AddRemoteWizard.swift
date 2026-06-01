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
                .rgInlineNavTitle()
                #endif
                .toolbar {
                    // Les étapes sont échangées via state.step dans un seul
                    // NavigationStack (pas de push), donc le bouton retour système
                    // n'apparaît pas — on en fournit un explicite dès qu'on a
                    // dépassé la 1re étape. state.goBack() respecte le flux
                    // (OAuth conditionnel, mode CLI).
                    if state.step != .nameAndBackend {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                state.goBack()
                            } label: {
                                Label("Retour", systemImage: "chevron.backward")
                            }
                        }
                    }
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
        case .interactiveCLI:
            InteractiveCLIView(state: state, onCreated: handleCreated)
        }
    }

    private var navigationTitle: String {
        switch state.step {
        case .nameAndBackend: return String(localized: "Nouveau remote")
        case .formFields:     return state.selectedBackend?.displayName ?? String(localized: "Configuration")
        case .oauth:          return String(localized: "Authentification")
        case .recapAndTest:   return String(localized: "Récapitulatif")
        case .interactiveCLI: return String(localized: "Mode interactif (CLI)")
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
        // "Tester" step, undo it before dismissing. We dismiss only
        // AFTER the delete resolves to avoid a race where the user
        // re-opens the wizard with the same name and the detached
        // cleanup deletes the freshly-recreated remote.
        guard state.remoteWasPreCreated, !state.name.isEmpty else {
            dismiss()
            return
        }
        let nameSnapshot = state.name
        Task {
            struct DeleteInput: Encodable { let name: String }
            let json = (try? JSONEncoder().encode(DeleteInput(name: nameSnapshot)))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            _ = try? await RcloneCore.shared.rpcRaw("config/delete", json)
            await RcloneCore.shared.invalidateConfigCache()
            await LogService.shared.log(
                .info,
                category: "wizard",
                message: "Wizard canceled — cleaned up orphan remote \(nameSnapshot)"
            )
            dismiss()
        }
    }

    private func handleCreated() {
        onSaved()
        dismiss()
    }
}

#Preview {
    AddRemoteWizard(onSaved: {})
}
