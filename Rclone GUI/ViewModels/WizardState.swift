//
//  WizardState.swift
//  Rclone GUI — ViewModels
//
//  Observable state shared by all four screens of AddRemoteWizard.
//  Lives on the main actor because every consumer is a SwiftUI View.
//
//  Lifecycle:
//  - Constructed when the wizard sheet is presented.
//  - Disposed when the sheet is dismissed (no persistence across sessions
//    is needed — the wizard is short-lived).
//

import Foundation
import Observation

@MainActor
@Observable
final class WizardState {

    // MARK: - Steps

    enum Step: Sendable, Hashable {
        case nameAndBackend
        case formFields
        case cryptConfig
        case oauth
        case recapAndTest
        case interactiveCLI
    }

    // MARK: - Test result

    enum TestResult: Sendable, Equatable {
        case notTested
        case inProgress
        case success(itemCount: Int, sample: [String])
        case failure(message: String)
        case timeout
    }

    // MARK: - Navigation

    var step: Step = .nameAndBackend

    // MARK: - Step 1 — Name & backend

    var name: String = ""
    var selectedBackend: BackendSchema?
    var existingRemoteNames: Set<String> = []
    var searchQuery: String = ""

    // MARK: - Step 2 — Form

    /// Live form values keyed by FieldSpec.name. Initialized from
    /// `defaultStr` when the user picks a backend, then mutated as they
    /// fill the form.
    var fieldValues: [String: String] = [:]

    /// Optional user-supplied OAuth credentials (override rclone's
    /// public defaults to avoid shared rate limits).
    var customClientID: String = ""
    var customClientSecret: String = ""

    /// `true` when the user opted into the interactive CLI flow from
    /// step 1. Bypasses the graphical form/OAuth/recap path entirely.
    var useInteractiveCLI: Bool = false

    // MARK: - Crypt (guided flow) — wraps an existing remote + folder

    /// Name of the underlying (plaintext) remote that crypt will wrap.
    var cryptUnderlyingRemote: String = ""
    /// Folder path inside the underlying remote where the vault lives
    /// (empty = the remote root).
    var cryptFolderPath: String = ""
    var cryptPassword: String = ""
    /// Optional salt (rclone `password2`).
    var cryptPassword2: String = ""
    /// `standard` | `obfuscate` | `off`.
    var cryptFilenameEncryption: String = "standard"
    var cryptDirNameEncryption: Bool = true

    // MARK: - Step 3 — OAuth

    var oauthCompleted: Bool = false
    var oauthError: String?

    // MARK: - Step 4 — Test & finalize

    var testResult: TestResult = .notTested
    var configCreateError: String?

    /// Set to `true` once `config/create` has actually written the
    /// remote section to rclone.conf — used so that "Annuler" later
    /// can clean up via `config/delete`.
    var remoteWasPreCreated: Bool = false

    // MARK: - Validation

    /// Validates the rclone-conf section name. Mirrors the rules in
    /// `RcloneConfigEditor.isValidRemoteName(_:)` to avoid surprises at
    /// save time.
    var nameIsValid: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let invalid = CharacterSet(charactersIn: ":[]/\\\n\r")
        return trimmed.rangeOfCharacter(from: invalid) == nil
    }

    var nameAlreadyExists: Bool {
        existingRemoteNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canProceedFromStep1: Bool {
        nameIsValid && !nameAlreadyExists && selectedBackend != nil
    }

    var canProceedFromStep2: Bool {
        guard let backend = selectedBackend else { return false }
        let providerValue = fieldValues["provider"]
        for field in backend.requiredVisibleFields(for: providerValue) {
            let value = fieldValues[field.name] ?? ""
            if value.trimmingCharacters(in: .whitespaces).isEmpty {
                return false
            }
        }
        return true
    }

    var requiresOAuthStep: Bool {
        selectedBackend?.requiresOAuth ?? false
    }

    /// `true` when the selected backend is rclone `crypt` — routed through the
    /// guided crypt flow (pick remote + folder + password) instead of the
    /// generic dynamic form.
    var isCrypt: Bool {
        selectedBackend?.name == "crypt"
    }

    /// The `remote` parameter for a crypt config: `<underlying>:<folder>`
    /// (or `<underlying>:` for the root).
    var cryptRemoteValue: String {
        let folder = cryptFolderPath.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        return folder.isEmpty ? "\(cryptUnderlyingRemote):" : "\(cryptUnderlyingRemote):\(folder)"
    }

    var canProceedFromCrypt: Bool {
        !cryptUnderlyingRemote.isEmpty && !cryptPassword.isEmpty
    }

    /// Pushes the guided crypt selections into `fieldValues` so the recap and
    /// `config/create` steps see them like any other backend.
    func commitCryptFieldValues() {
        var values: [String: String] = [:]
        values["remote"] = cryptRemoteValue
        values["password"] = cryptPassword
        if !cryptPassword2.isEmpty { values["password2"] = cryptPassword2 }
        values["filename_encryption"] = cryptFilenameEncryption
        values["directory_name_encryption"] = cryptDirNameEncryption ? "true" : "false"
        fieldValues = values
    }

    // MARK: - Navigation helpers

    func advance() {
        switch step {
        case .nameAndBackend:
            if useInteractiveCLI {
                step = .interactiveCLI
            } else if isCrypt {
                step = .cryptConfig
            } else {
                initializeFormValues()
                step = .formFields
            }
        case .cryptConfig:
            commitCryptFieldValues()
            step = .recapAndTest
        case .formFields:
            step = requiresOAuthStep ? .oauth : .recapAndTest
        case .oauth:
            step = .recapAndTest
        case .recapAndTest, .interactiveCLI:
            break
        }
    }

    func goBack() {
        switch step {
        case .nameAndBackend:
            break
        case .cryptConfig:
            step = .nameAndBackend
        case .formFields:
            step = .nameAndBackend
        case .oauth:
            step = .formFields
        case .recapAndTest:
            if isCrypt {
                step = .cryptConfig
            } else {
                step = requiresOAuthStep ? .oauth : .formFields
            }
        case .interactiveCLI:
            step = .nameAndBackend
            useInteractiveCLI = false
        }
    }

    /// Seed `fieldValues` with the rclone-provided defaults for the
    /// selected backend. Only called when transitioning from step 1
    /// to step 2 (or when the backend selection changes).
    func initializeFormValues() {
        guard let backend = selectedBackend else { return }
        var values: [String: String] = [:]
        for field in backend.formFields where !field.defaultStr.isEmpty {
            values[field.name] = field.defaultStr
        }
        fieldValues = values
    }
}
