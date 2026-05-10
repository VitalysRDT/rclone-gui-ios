//
//  FieldValidator.swift
//  Rclone GUI — Models/Wizard
//
//  Pre-submission validation for FieldSpec values. We validate the
//  obvious type constraints (int parsable, SizeSuffix/Duration regex)
//  client-side to give immediate feedback; rclone itself runs a deeper
//  validation pass on `config/create` that catches semantic errors
//  (e.g. unreachable host, invalid credentials).
//

import Foundation

enum FieldValidationError: Error, Sendable, Hashable {
    case required
    case invalidInt
    case invalidSizeSuffix
    case invalidDuration
    case invalidTristate
}

extension FieldValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .required:          return "Requis"
        case .invalidInt:        return "Doit être un nombre entier"
        case .invalidSizeSuffix: return "Format invalide (ex : 100M, 5G, 1Ki)"
        case .invalidDuration:   return "Format invalide (ex : 10s, 5m, 2h)"
        case .invalidTristate:   return "Doit être true, false ou vide"
        }
    }
}

extension FieldSpec {

    /// Validate a raw user input. Returns `nil` if valid.
    func validate(_ rawValue: String) -> FieldValidationError? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if required && trimmed.isEmpty {
            return .required
        }

        guard !trimmed.isEmpty else { return nil }  // optional + empty = OK

        switch type {
        case "int":
            return Int(trimmed) == nil ? .invalidInt : nil

        case "SizeSuffix":
            // Examples: 100, 100K, 100M, 100G, 100T, 100P, 100Ki, 100Mi, 100Gi, 100Ti, 100Pi
            let pattern = #"^[0-9]+(\.[0-9]+)?(B|K|M|G|T|P|Ki|Mi|Gi|Ti|Pi)?$"#
            return trimmed.range(of: pattern, options: .regularExpression) == nil
                ? .invalidSizeSuffix : nil

        case "Duration":
            // Examples: 10ns, 10us, 10µs, 10ms, 10s, 5m, 2h
            let pattern = #"^[0-9]+(\.[0-9]+)?(ns|us|µs|ms|s|m|h)?$"#
            return trimmed.range(of: pattern, options: .regularExpression) == nil
                ? .invalidDuration : nil

        case "Tristate":
            return ["true", "false"].contains(trimmed.lowercased()) ? nil : .invalidTristate

        default:
            return nil
        }
    }
}
