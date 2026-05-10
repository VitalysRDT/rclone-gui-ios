//
//  FieldRow.swift
//  Rclone GUI — Views/Settings/AddRemote/Components
//
//  Renders one FieldSpec value as the appropriate SwiftUI control.
//  Switches on `FieldSpec.uiKind` so the dynamic form (which iterates
//  over `BackendSchema.formFields`) stays a thin ForEach + this row.
//
//  All controls are inside a Section (the parent form decides the
//  section), so we don't render any container chrome here.
//

import SwiftUI

struct FieldRow: View {

    let spec: FieldSpec
    @Binding var value: String

    /// Currently-selected provider value, used to filter Examples for
    /// fields like `region` whose suggestions depend on `provider`.
    var selectedProvider: String? = nil

    /// Validation error to show under the field, if any.
    var validationError: FieldValidationError?

    @State private var revealSecret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            label
            control
            footer
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Label

    @ViewBuilder
    private var label: some View {
        HStack(spacing: 6) {
            Text(spec.label)
                .font(.subheadline.weight(.semibold))
            if spec.required {
                Text("• requis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Control

    @ViewBuilder
    private var control: some View {
        switch spec.uiKind {
        case .textInput:
            TextField(spec.placeholder, text: $value, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...3)

        case .secureInput:
            HStack {
                Group {
                    if revealSecret {
                        TextField(spec.placeholder, text: $value)
                    } else {
                        SecureField(spec.placeholder, text: $value)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    revealSecret.toggle()
                } label: {
                    Image(systemName: revealSecret ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(revealSecret ? "Masquer" : "Afficher")
            }

        case .toggle:
            Toggle(spec.label, isOn: Binding(
                get: { value == "true" },
                set: { value = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

        case .numberInput:
            #if os(iOS)
            TextField(spec.placeholder, text: $value)
                .keyboardType(.numberPad)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            #else
            TextField(spec.placeholder, text: $value)
                .autocorrectionDisabled()
            #endif

        case .picker:
            Picker(spec.label, selection: $value) {
                if value.isEmpty || !exampleValues.contains(where: { $0.value == value }) {
                    Text("— choisir —").tag(value)
                }
                ForEach(visibleExamples, id: \.value) { example in
                    Text(exampleLabel(example)).tag(example.value)
                }
            }
            .labelsHidden()

        case .combobox:
            VStack(alignment: .leading, spacing: 8) {
                if !visibleExamples.isEmpty {
                    Picker("Suggestions", selection: $value) {
                        Text("Personnalisé…").tag("")
                        ForEach(visibleExamples, id: \.value) { example in
                            Text(exampleLabel(example)).tag(example.value)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                TextField(spec.placeholder, text: $value)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

        case .tristate:
            Picker(spec.label, selection: $value) {
                Text("Par défaut").tag("")
                Text("Oui").tag("true")
                Text("Non").tag("false")
            }
            .labelsHidden()
            .pickerStyle(.segmented)

        case .datePicker:
            // Time fields are extremely rare (2 occurrences across all
            // 950 options). For now we just show a TextField; a real
            // DatePicker can come later when a use-case appears.
            TextField(spec.placeholder, text: $value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

        case .oauth:
            // OAuth-related fields are managed by the dedicated OAuth
            // step; we shouldn't be rendering this case in the form.
            EmptyView()
        }
    }

    // MARK: - Footer (help + validation)

    @ViewBuilder
    private var footer: some View {
        if let error = validationError {
            Label(error.errorDescription ?? "Erreur", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        } else if let hint = spec.validationHint {
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if !spec.help.isEmpty {
            Text(spec.help.split(separator: "\n").first.map(String.init) ?? spec.help)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private var visibleExamples: [RcloneExampleValue] {
        spec.examples(for: selectedProvider)
    }

    private var exampleValues: [RcloneExampleValue] {
        spec.examples
    }

    private func exampleLabel(_ example: RcloneExampleValue) -> String {
        let helpExcerpt = example.help.split(separator: "\n").first.map(String.init) ?? ""
        if helpExcerpt.isEmpty || helpExcerpt.count > 60 {
            return example.value
        }
        return "\(example.value) — \(helpExcerpt)"
    }

    private var accessibilityLabel: String {
        var components: [String] = [spec.label]
        if spec.required { components.append("requis") }
        if spec.sensitive { components.append("sécurisé") }
        return components.joined(separator: ", ")
    }
}
