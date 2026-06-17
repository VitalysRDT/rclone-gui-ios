//
//  FieldUIKind.swift
//  Rclone GUI — Models/Wizard
//
//  UI-side classification of a backend option. Derived from the raw
//  rclone Type + metadata (Sensitive, Examples, Exclusive). Keeps the
//  view layer dumb — every FieldRow just switches on this enum.
//

import Foundation

enum FieldUIKind: Sendable, Hashable {
    /// Plain TextField (string, SizeSuffix, Duration, Encoding, Bits, lists, etc.).
    case textInput

    /// SecureField for sensitive values (password, secret, token).
    case secureInput

    /// Toggle for booleans.
    case toggle

    /// TextField with `.numberPad` keyboard.
    case numberInput

    /// Picker constrained to the option's `Examples` (Exclusive=true).
    case picker

    /// Picker with free-form input fallback (Examples present, Exclusive=false).
    case combobox

    /// Three-way picker (Yes / No / Default) for rclone's Tristate type.
    case tristate

    /// DatePicker for the rare Time-typed options.
    case datePicker

    /// File-backed option: the backend wants a file on disk (SSH private key,
    /// service-account JSON, certificate, known_hosts…) or inline file content
    /// (`key_pem`). Rendered as an "Import a file…" control that reads the file
    /// via the iOS document picker — a filesystem path is meaningless to type
    /// on iOS. See `FieldSpec.fileFieldKind`.
    case fileImport

    /// OAuth field (token / auth_url / token_url) — handled outside the
    /// dynamic form, in the dedicated OAuth step.
    case oauth
}
