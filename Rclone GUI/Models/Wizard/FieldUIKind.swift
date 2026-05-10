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

    /// OAuth field (token / auth_url / token_url) — handled outside the
    /// dynamic form, in the dedicated OAuth step.
    case oauth
}
