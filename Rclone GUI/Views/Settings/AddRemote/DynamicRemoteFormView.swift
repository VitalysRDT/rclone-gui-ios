//
//  DynamicRemoteFormView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Step 2: dynamic form generated from `BackendSchema.formFields`.
//  - Required + non-Advanced fields appear at the top in a "Configuration"
//    section.
//  - Advanced fields are tucked behind a DisclosureGroup so the user
//    isn't overwhelmed (s3 has 64 advanced fields, drive has 47).
//  - When a backend exposes a `provider` field (e.g. s3), it is always
//    rendered first because many other fields are conditioned on its
//    value via the `Provider` filter.
//

import SwiftUI

struct DynamicRemoteFormView: View {

    @Bindable var state: WizardState

    let onNext: () -> Void

    @State private var showAdvanced = false

    var body: some View {
        Form {
            if let backend = state.selectedBackend {
                headerSection(for: backend)
                if let providerField = providerField(in: backend) {
                    providerSection(field: providerField)
                }
                primarySection(for: backend)
                advancedSection(for: backend)
                if backend.requiresOAuth {
                    oauthHintSection(for: backend)
                }
            } else {
                Section {
                    Label("Aucun backend sélectionné. Reviens à l'étape précédente.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Suivant") { onNext() }
                    .disabled(!state.canProceedFromStep2)
            }
        }
    }

    // MARK: - Sections

    private func headerSection(for backend: BackendSchema) -> some View {
        Section {
            HStack(spacing: 14) {
                AppIconTile(systemImage: backend.icon, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.displayName)
                        .font(.body.weight(.semibold))
                    Text(backend.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func providerSection(field: FieldSpec) -> some View {
        Section {
            FieldRow(
                spec: field,
                value: binding(for: field.name),
                selectedProvider: state.fieldValues["provider"]
            )
        } header: {
            Text("Provider")
        } footer: {
            Text("Le choix du provider détermine quels champs sont disponibles plus bas.")
        }
    }

    private func primarySection(for backend: BackendSchema) -> some View {
        let fields = primaryFields(for: backend)
        return Section {
            if fields.isEmpty {
                Text("Aucun champ obligatoire pour ce backend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fields) { field in
                    FieldRow(
                        spec: field,
                        value: binding(for: field.name),
                        selectedProvider: state.fieldValues["provider"],
                        validationError: validationError(for: field)
                    )
                }
            }
        } header: {
            Text("Configuration")
        }
    }

    @ViewBuilder
    private func advancedSection(for backend: BackendSchema) -> some View {
        let fields = advancedFields(for: backend)
        if !fields.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showAdvanced) {
                    ForEach(fields) { field in
                        FieldRow(
                            spec: field,
                            value: binding(for: field.name),
                            selectedProvider: state.fieldValues["provider"],
                            validationError: validationError(for: field)
                        )
                    }
                } label: {
                    Label("Options avancées (\(fields.count))", systemImage: "gearshape.2")
                }
            }
        }
    }

    private func oauthHintSection(for backend: BackendSchema) -> some View {
        Section {
            Label("Authentification \(backend.displayName) à l'étape suivante.",
                  systemImage: "lock.shield.fill")
                .font(.callout)
                .foregroundStyle(.tint)
        }
    }

    // MARK: - Field selection helpers

    private func providerField(in backend: BackendSchema) -> FieldSpec? {
        // Show "provider" first only when it's a real Exclusive picker
        // (= the backend uses sub-providers). Other "provider" strings
        // (rare) stay in the regular flow.
        guard let field = backend.formFields.first(where: { $0.name == "provider" }) else {
            return nil
        }
        return field.exclusive ? field : nil
    }

    private func primaryFields(for backend: BackendSchema) -> [FieldSpec] {
        let providerName = state.fieldValues["provider"]
        return backend.formFields.filter { field in
            // Skip the provider field if we already render it in its own section.
            if let separated = providerField(in: backend), separated.id == field.id {
                return false
            }
            guard !field.advanced else { return false }
            return field.isVisible(for: providerName)
        }
    }

    private func advancedFields(for backend: BackendSchema) -> [FieldSpec] {
        let providerName = state.fieldValues["provider"]
        return backend.formFields.filter { field in
            field.advanced && field.isVisible(for: providerName)
        }
    }

    // MARK: - Bindings & validation

    private func binding(for fieldName: String) -> Binding<String> {
        Binding(
            get: { state.fieldValues[fieldName] ?? "" },
            set: { state.fieldValues[fieldName] = $0 }
        )
    }

    private func validationError(for field: FieldSpec) -> FieldValidationError? {
        let value = state.fieldValues[field.name] ?? ""
        // Don't show "required" until the user has tried to advance —
        // showing it on initial render is just visual noise.
        let error = field.validate(value)
        if error == .required && value.isEmpty { return nil }
        return error
    }
}
