//
//  BackendSchema.swift
//  Rclone GUI — Models/Wizard
//
//  Fused product model of a backend: the raw rclone schema + the Swift
//  overrides (category, icon, FR description, OAuth config). Built once
//  by `RemoteCatalogService` and consumed by every wizard view.
//

import Foundation

struct BackendSchema: Identifiable, Hashable, Sendable {
    /// Backend name (e.g. "drive"). Doubles as id.
    var id: String { name }

    let name: String
    let prefix: String
    let displayName: String
    let description: String
    let category: BackendCategory
    let icon: String
    let fields: [FieldSpec]
    let oauthConfig: OAuthProviderConfig?

    /// `true` when this backend triggers the dedicated OAuth wizard step.
    var requiresOAuth: Bool { oauthConfig != nil }

    /// Fields shown in the dynamic form. Excludes:
    /// - hidden fields (`hide != 0`)
    /// - OAuth-specific fields managed by the OAuth step
    var formFields: [FieldSpec] {
        var oauthHidden: Set<String> = [
            "token", "auth_url", "token_url", "client_secret"
        ]
        // Quand un backend passe par l'étape d'auth guidée (OAuthView), le champ
        // qu'elle collecte (ex : Drime `access_token`, Filen `api_key`, Box
        // `access_token`) ne doit PAS réapparaître aussi dans le formulaire
        // dynamique — sinon l'utilisateur le voit en double. L'étape OAuth écrit
        // directement dans fieldValues, donc config/create le reçoit quand même.
        if let tokenField = oauthConfig?.tokenFieldName {
            oauthHidden.insert(tokenField)
        }
        return fields.filter { spec in
            spec.hide == 0 && !oauthHidden.contains(spec.name)
        }
    }

    /// Convenience: required form fields visible for the current
    /// provider value (used to drive the "Suivant" button enable state).
    func requiredVisibleFields(for selectedProvider: String?) -> [FieldSpec] {
        formFields.filter { spec in
            spec.required && spec.isVisible(for: selectedProvider)
        }
    }
}
