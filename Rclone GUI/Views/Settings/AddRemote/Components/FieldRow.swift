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
import UniformTypeIdentifiers

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
            TextField(spec.label, text: $value, prompt: Text(spec.placeholder), axis: .vertical)
                .labelsHidden()
                .rgNoAutocap()
                .autocorrectionDisabled()
                .lineLimit(1...3)

        case .secureInput:
            HStack {
                Group {
                    if revealSecret {
                        TextField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
                    } else {
                        SecureField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
                    }
                }
                .rgNoAutocap()
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
            TextField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
                .keyboardType(.numberPad)
                .rgNoAutocap()
                .autocorrectionDisabled()
            #else
            TextField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
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
                TextField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
                    .rgNoAutocap()
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
            TextField(spec.label, text: $value, prompt: Text(spec.placeholder)).labelsHidden()
                .rgNoAutocap()
                .autocorrectionDisabled()

        case .fileImport:
            FileImportControl(spec: spec, value: $value)

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

// MARK: - File import control

/// Renders a `.fileImport` field: a button that opens the iOS/macOS document
/// picker. For `.path` options the picked file is copied into the app's secure
/// container and the field stores that path; for `.inlineContent` options the
/// field stores the file's text directly. Manual entry stays available for
/// path options (power users pasting an existing in-container path).
private struct FileImportControl: View {

    let spec: FieldSpec
    @Binding var value: String

    @State private var presentingPicker = false
    @State private var importedName: String?
    @State private var importError: String?

    private var kind: FieldSpec.FileFieldKind {
        spec.fileFieldKind ?? .path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !value.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text(summary)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(role: .destructive) {
                        clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retirer le fichier")
                }
            }

            Button {
                presentingPicker = true
            } label: {
                Label(
                    value.isEmpty ? "Importer un fichier…" : "Remplacer le fichier…",
                    systemImage: "doc.badge.arrow.up"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Manual path entry stays possible for path-typed options.
            if kind == .path {
                TextField("ou saisir un chemin", text: $value)
                    .rgNoAutocap()
                    .autocorrectionDisabled()
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $presentingPicker,
            allowedContentTypes: [.data, .text, .json],
            allowsMultipleSelection: false
        ) { result in
            handle(result)
        }
    }

    private var summary: String {
        if let importedName { return importedName }
        switch kind {
        case .inlineContent:
            return String(localized: "Contenu importé")
        case .path:
            return URL(fileURLWithPath: value).lastPathComponent
        }
    }

    private var hint: String {
        switch kind {
        case .inlineContent:
            return String(localized: "Importez le fichier (clé PEM, JSON…) — son contenu est enregistré directement.")
        case .path:
            return String(localized: "Importez le fichier requis — il est copié en sécurité dans l'app, jamais transmis ailleurs.")
        }
    }

    private func handle(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            switch kind {
            case .inlineContent:
                value = try CredentialFileStore.readText(from: url)
            case .path:
                let dest = try CredentialFileStore.importFile(from: url, fieldName: spec.name)
                value = dest.path
            }
            importedName = url.lastPathComponent
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func clear() {
        if kind == .path {
            CredentialFileStore.removeFileIfManaged(atPath: value)
        }
        value = ""
        importedName = nil
        importError = nil
    }
}
