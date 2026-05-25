//
//  FieldSpec.swift
//  Rclone GUI — Models/Wizard
//
//  Product-side model of one backend field. Built from a raw
//  `RcloneOptionSchema` plus a few computed UI hints. Sendable + Hashable
//  so it composes cleanly with SwiftUI ForEach and @Observable state.
//

import Foundation

struct FieldSpec: Identifiable, Hashable, Sendable {
    /// Rclone option name (e.g. "access_key_id", "scope"). Doubles as id.
    let id: String
    let name: String

    /// User-facing label. Defaults to a humanized version of `name` when
    /// no FR translation is available; the view layer can override.
    let label: String

    /// Help text (markdown, multiline) directly from rclone. Hard-wrapped
    /// at 80 chars; URLs should be made clickable in the view.
    let help: String

    /// Raw rclone Type ("string", "bool", "int", "SizeSuffix", "Duration",
    /// "Tristate", "Encoding", "Bits", "CommaSepList", "SpaceSepList",
    /// "Time", "stringArray").
    let type: String

    /// Default value as advertised by rclone (string-encoded).
    let defaultStr: String

    let required: Bool
    let isPassword: Bool
    let sensitive: Bool
    let advanced: Bool
    let exclusive: Bool

    /// Bitmask. != 0 means rclone wants this field hidden in some contexts.
    /// We respect it strictly: if `hide != 0`, the field is not rendered.
    let hide: Int

    /// Suggested values. May be empty.
    let examples: [RcloneExampleValue]

    /// Comma-separated list of providers this option applies to (e.g.
    /// "AWS,Cloudflare,Wasabi"). When set, the option is hidden when the
    /// currently-selected provider is not in the list.
    let providerFilter: String?

    // MARK: - Lifting from rclone schema

    nonisolated init(from option: RcloneOptionSchema, label overrideLabel: String? = nil) {
        self.id = option.name
        self.name = option.name
        self.label = overrideLabel ?? Self.humanize(option.name)
        self.help = option.help
        self.type = option.type
        self.defaultStr = option.defaultStr
        self.required = option.required
        self.isPassword = option.isPassword
        self.sensitive = option.sensitive
        self.advanced = option.advanced
        self.exclusive = option.exclusive
        self.hide = option.hide
        self.examples = option.examples ?? []
        self.providerFilter = option.provider
    }

    private static func humanize(_ raw: String) -> String {
        // "access_key_id" → "Access Key Id"
        raw.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    // MARK: - UI hints

    /// Initial form value for this field.
    var initialValue: String { defaultStr }

    /// Allowed providers parsed from `providerFilter`.
    var allowedProviders: Set<String>? {
        guard let raw = providerFilter, !raw.isEmpty else { return nil }
        return Set(
            raw.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
        )
    }

    /// `true` when the field should be rendered given the currently
    /// selected provider value (relevant for backends like S3 that have
    /// dozens of conditional fields).
    func isVisible(for selectedProvider: String?) -> Bool {
        guard let allowed = allowedProviders else { return true }
        return selectedProvider.map { allowed.contains($0) } ?? false
    }

    /// Examples filtered by the selected provider. Examples without a
    /// provider tag are always returned.
    func examples(for selectedProvider: String?) -> [RcloneExampleValue] {
        examples.filter { ex in
            guard let raw = ex.provider, !raw.isEmpty else { return true }
            let allowed = Set(
                raw.split(separator: ",").map {
                    String($0).trimmingCharacters(in: .whitespaces)
                }
            )
            return selectedProvider.map { allowed.contains($0) } ?? true
        }
    }

    /// What kind of UI control to render.
    var uiKind: FieldUIKind {
        if name == "token" { return .oauth }
        if sensitive || isPassword { return .secureInput }

        if !examples.isEmpty {
            return exclusive ? .picker : .combobox
        }

        switch type {
        case "bool":     return .toggle
        case "int":      return .numberInput
        case "Tristate": return .tristate
        case "Time":     return .datePicker
        default:         return .textInput
        }
    }

    /// Helper string shown under tricky text fields (size, duration, …).
    var validationHint: String? {
        switch type {
        case "SizeSuffix":   return String(localized: "Format : 100M, 5G, 1Ki…")
        case "Duration":     return String(localized: "Format : 10s, 5m, 2h…")
        case "Encoding":     return String(localized: "Encodage rclone (laisser par défaut sauf besoin spécifique)")
        case "Bits":         return String(localized: "Combinaison de flags (séparés par virgule)")
        case "CommaSepList": return String(localized: "Liste séparée par virgules")
        case "SpaceSepList": return String(localized: "Liste séparée par espaces")
        default:             return nil
        }
    }

    /// Placeholder text for the input control.
    var placeholder: String {
        if !defaultStr.isEmpty { return defaultStr }
        if let firstExample = examples.first { return firstExample.value }
        return label
    }
}
