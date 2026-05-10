//
//  BackendListRow.swift
//  Rclone GUI — Views/Settings/AddRemote/Components
//
//  One row of the backend picker. Shows icon + display name + short
//  description, plus a discreet badge for OAuth-required backends so
//  the user knows ahead of time whether they'll go through a sign-in
//  flow.
//

import SwiftUI

struct BackendListRow: View {

    let backend: BackendSchema
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            AppIconTile(
                systemImage: backend.icon,
                tint: tint,
                size: 38,
                iconSize: .body
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(backend.displayName)
                    .font(.body.weight(.semibold))
                Text(backend.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if backend.requiresOAuth {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Requiert une authentification")
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(backend.displayName))
        .accessibilityHint(Text(backend.description))
    }

    private var tint: Color {
        switch backend.category {
        case .officialCloud: return .blue
        case .s3Compatible:  return .orange
        case .mainstream:    return .purple
        case .selfHosted:    return .green
        case .specialized:   return .pink
        case .wrapper:       return .indigo
        case .local:         return .gray
        }
    }
}
