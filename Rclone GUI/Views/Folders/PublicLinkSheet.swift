//
//  PublicLinkSheet.swift
//  Rclone GUI — Views/Folders
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct PublicLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    let remote: String
    let entry: RemoteEntryDTO

    @State private var customBaseURL = ""
    @State private var pathPrefixToRemove = ""
    @State private var nativeURL: URL?
    @State private var supportsNativeLink: Bool?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var confirmationMessage: String?

    private var customURL: URL? {
        guard let baseURL = PublicLinkFormatter.normalizedBaseURL(from: customBaseURL) else {
            return nil
        }
        return PublicLinkFormatter.customURL(
            baseURL: baseURL,
            remotePath: entry.pathInRemote,
            removingPathPrefix: pathPrefixToRemove
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if let customURL {
                    linkSection(title: "Lien CDN personnalisé", url: customURL)
                }

                Section {
                    urlTextField
                    TextField("Préfixe de chemin à supprimer (facultatif)", text: $pathPrefixToRemove)
                        .autocorrectionDisabled(true)

                    HStack {
                        Button("Enregistrer") { saveCustomDomain() }
                            .buttonStyle(.borderedProminent)
                        if !customBaseURL.isEmpty {
                            Button("Effacer", role: .destructive) {
                                customBaseURL = ""
                                pathPrefixToRemove = ""
                                _ = RemotePublicLinkSettingsStore.setCustomBaseURL("", for: remote)
                                _ = RemotePublicLinkSettingsStore.setPathPrefixToRemove("", for: remote)
                                confirmationMessage = String(localized: "Domaine CDN supprimé.")
                            }
                        }
                    }
                } header: {
                    Text("Domaine CDN de \(remote)")
                } footer: {
                    Text("Le domaine doit pointer vers la racine publique de ce remote ou de ce bucket. L’app ajoute automatiquement le chemin du fichier ; elle ne modifie pas les permissions du stockage. Si le chemin commence par un préfixe de bucket, saisis-le dans le champ facultatif pour le retirer de l’URL CDN.")
                }

                Section {
                    if let nativeURL {
                        linkActions(url: nativeURL)
                    } else if supportsNativeLink == nil {
                        HStack {
                            ProgressView()
                            Text("Vérification de la compatibilité…")
                        }
                    } else if supportsNativeLink == true {
                        Button {
                            Task { await generateNativeLink() }
                        } label: {
                            Label {
                                Text(isGenerating
                                     ? String(localized: "Génération…")
                                     : String(localized: "Générer via rclone"))
                            } icon: {
                                Image(systemName: "link.badge.plus")
                            }
                        }
                        .disabled(isGenerating)
                    } else {
                        Label(
                            "Ce backend ne signale pas la création de liens publics. Configure un domaine CDN ci-dessus.",
                            systemImage: "info.circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Lien public rclone")
                } footer: {
                    Text("Selon le fournisseur, générer ce lien peut rendre le fichier accessible à toute personne qui possède l’URL.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let confirmationMessage {
                    Section {
                        Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Lien public")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .task {
            customBaseURL = RemotePublicLinkSettingsStore.customBaseURL(for: remote)
            pathPrefixToRemove = RemotePublicLinkSettingsStore.pathPrefixToRemove(for: remote)
            supportsNativeLink = await RemoteService.shared.supportsPublicLink(remote: remote)
        }
    }

    @ViewBuilder
    private var urlTextField: some View {
        let field = TextField("https://img.example.com", text: $customBaseURL)
            .textContentType(.URL)
            .autocorrectionDisabled(true)
        #if os(iOS)
        field
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
        #else
        field
        #endif
    }

    private func linkSection(title: LocalizedStringKey, url: URL) -> some View {
        Section(title) {
            linkActions(url: url)
        }
    }

    private func linkActions(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    copy(url.absoluteString, confirmation: String(localized: "Lien copié."))
                } label: {
                    Label("Copier l’URL", systemImage: "doc.on.doc")
                }

                Button {
                    copy(
                        PublicLinkFormatter.markdown(
                            url: url,
                            name: entry.name,
                            isDirectory: entry.isDirectory
                        ),
                        confirmation: String(localized: "Markdown copié.")
                    )
                } label: {
                    Label("Copier en Markdown", systemImage: "text.badge.checkmark")
                }

                Button {
                    copy(
                        PublicLinkFormatter.html(
                            url: url,
                            name: entry.name,
                            isDirectory: entry.isDirectory
                        ),
                        confirmation: String(localized: "HTML copié.")
                    )
                } label: {
                    Label("Copier en HTML", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            .buttonStyle(.bordered)

            ShareLink(item: url) {
                Label("Partager le lien", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func saveCustomDomain() {
        errorMessage = nil
        confirmationMessage = nil
        guard let stored = RemotePublicLinkSettingsStore.setCustomBaseURL(customBaseURL, for: remote) else {
            errorMessage = String(localized: "Saisis un domaine HTTP(S) valide, sans identifiants.")
            return
        }
        customBaseURL = stored
        pathPrefixToRemove = RemotePublicLinkSettingsStore.setPathPrefixToRemove(
            pathPrefixToRemove,
            for: remote
        )
        confirmationMessage = stored.isEmpty
            ? String(localized: "Domaine CDN supprimé.")
            : String(localized: "Domaine CDN enregistré.")
    }

    @MainActor
    private func generateNativeLink() async {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        confirmationMessage = nil
        defer { isGenerating = false }
        do {
            nativeURL = try await RemoteService.shared.createPublicLink(
                remote: remote,
                path: entry.pathInRemote
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copy(_ value: String, confirmation: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = value
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        errorMessage = nil
        confirmationMessage = confirmation
    }
}

struct RemotePublicLinkSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let remote: String

    @State private var customBaseURL = ""
    @State private var pathPrefixToRemove = ""
    @State private var errorMessage: String?
    @State private var supportsNativeLink: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://img.example.com", text: $customBaseURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled(true)
                    TextField("Préfixe de chemin à supprimer (facultatif)", text: $pathPrefixToRemove)
                        .autocorrectionDisabled(true)
                    Button("Enregistrer") { save() }
                        .buttonStyle(.borderedProminent)
                } header: {
                    Text("Domaine CDN personnalisé")
                } footer: {
                    Text("Ce domaine est enregistré uniquement sur cet appareil pour le remote « \(remote) ». Il doit déjà servir publiquement la racine du bucket. Pour Qiniu Kodo ou un autre backend qui renvoie le bucket dans le chemin, saisis ici le préfixe à retirer, par exemple `aab`.")
                }

                Section("Lien natif rclone") {
                    if supportsNativeLink == nil {
                        ProgressView()
                    } else {
                        Label {
                            Text(supportsNativeLink == true
                                 ? String(localized: "Ce backend prend en charge les liens publics.")
                                 : String(localized: "Ce backend ne signale pas la prise en charge des liens publics."))
                        } icon: {
                            Image(systemName: supportsNativeLink == true ? "checkmark.circle.fill" : "info.circle")
                        }
                        .foregroundStyle(
                            supportsNativeLink == true
                                ? AnyShapeStyle(.green)
                                : AnyShapeStyle(.secondary)
                        )
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Liens publics · \(remote)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .task {
            customBaseURL = RemotePublicLinkSettingsStore.customBaseURL(for: remote)
            pathPrefixToRemove = RemotePublicLinkSettingsStore.pathPrefixToRemove(for: remote)
            supportsNativeLink = await RemoteService.shared.supportsPublicLink(remote: remote)
        }
    }

    private func save() {
        guard let stored = RemotePublicLinkSettingsStore.setCustomBaseURL(customBaseURL, for: remote) else {
            errorMessage = String(localized: "Saisis un domaine HTTP(S) valide, sans identifiants.")
            return
        }
        customBaseURL = stored
        pathPrefixToRemove = RemotePublicLinkSettingsStore.setPathPrefixToRemove(
            pathPrefixToRemove,
            for: remote
        )
        errorMessage = nil
        dismiss()
    }
}
