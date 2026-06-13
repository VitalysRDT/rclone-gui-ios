//
//  ImportConfigView.swift
//  Rclone GUI — Views/Settings
//
//  Wraps UIDocumentPickerViewController so the user can pick a
//  rclone.conf from Files.app / iCloud / AirDrop, then encrypts it
//  via ConfigStore for at-rest storage.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportConfigView: View {
    let onImported: () -> Void

    @State private var importing = false
    @State private var error: String?
    @State private var success: String?
    @State private var rclonePassword = ""
    /// Config chiffrée (RCLONE_ENCRYPT_V0) déjà lue depuis Fichiers,
    /// en attente du mot de passe rclone pour être déchiffrée.
    @State private var pendingEncrypted: Data?
    @State private var decrypting = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    importHeader

                    // MARK: Source
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Source")
                        VStack(spacing: 0) {
                            Button {
                                importing = true
                            } label: {
                                importSourceRow(
                                    icon: "folder.fill",
                                    tint: .blue,
                                    title: "Depuis Fichiers",
                                    subtitle: "rclone.conf"
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            rowDivider
                            importSourceRow(
                                icon: "qrcode",
                                tint: .green,
                                title: "Scanner un QR",
                                subtitle: "rclone config dump | qrencode",
                                disabled: true
                            )
                            rowDivider
                            importSourceRow(
                                icon: "globe",
                                tint: .indigo,
                                title: "URL / iCloud",
                                subtitle: "Bientôt",
                                disabled: true
                            )
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color.rgGroupedRowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Le fichier sera chiffré et stocké localement. Tes clés ne quittent jamais ton appareil.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    // MARK: Mot de passe rclone
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Mot de passe rclone")
                        HStack(spacing: 8) {
                            Image(systemName: "lock")
                                .foregroundStyle(.secondary)
                            SecureField("Mot de passe rclone (optionnel)", text: $rclonePassword)
                                .textContentType(.password)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                        }
                        .padding(12)
                        .background(Color.rgGroupedRowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        Text("Requis uniquement si ton rclone.conf est chiffré (« rclone config encryption set »). Utilisé une seule fois pour déchiffrer à l'import, jamais stocké.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if pendingEncrypted != nil {
                            Button {
                                Task { await decryptPending() }
                            } label: {
                                HStack {
                                    if decrypting {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "lock.open.fill")
                                    }
                                    Text("Déchiffrer et importer")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(rclonePassword.isEmpty || decrypting)
                        }
                    }

                    if let success {
                        AppInlineMessage(title: "Configuration importée", message: LocalizedStringKey(success), systemImage: "checkmark.circle.fill", tint: .green)
                    } else if let error {
                        AppInlineMessage(title: "Import impossible", message: LocalizedStringKey(error), systemImage: "exclamationmark.triangle.fill", tint: .red)
                    }
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.rgGroupedBackground)
            .navigationTitle("Importer")
            #if os(iOS)
            .rgInlineNavTitle()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            // .fileImporter est cross-platform (iOS + macOS) et présente le
            // sélecteur natif correctement même depuis une sheet — contrairement
            // à NSOpenPanel.runModal() qui peut ne pas s'afficher dans ce contexte.
            .fileImporter(
                isPresented: $importing,
                allowedContentTypes: Self.allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await load(url) }
                case .failure(let err):
                    error = "Échec de l'import : \(err.localizedDescription)"
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 560)
        #endif
    }

    private var importHeader: some View {
        HStack(spacing: 14) {
            RGCryptSeal(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import rclone.conf")
                    .font(.system(size: 20, weight: .bold))
                Text("Chiffré localement (Secure Enclave + biométrie)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 40)
    }

    private func importSourceRow(
        icon: String,
        tint: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(disabled ? .secondary : .primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !disabled {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .opacity(disabled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    private static let allowedContentTypes: [UTType] = [
        .data,
        UTType(filenameExtension: "conf") ?? .data,
        .plainText,
        .text,
        UTType(filenameExtension: "rclonebackup") ?? .data,
    ]

    private func load(_ url: URL) async {
        do {
            // UIDocumentPicker hands us a security-scoped URL ; we must
            // explicitly request access for the duration of the read.
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)

            // Une config chiffrée par rclone (RCLONE_ENCRYPT_V0) ne doit
            // jamais être stockée telle quelle : librclone ne peut pas la
            // lire sans mot de passe et son chemin d'erreur est fatal (crash
            // au lancement). On déchiffre ici, à l'import.
            if ConfigStore.isRcloneEncrypted(data) {
                if rclonePassword.isEmpty {
                    pendingEncrypted = data
                    error = String(localized: "Cette configuration est chiffrée par rclone. Saisis ton mot de passe ci-dessus puis touche « Déchiffrer et importer ».")
                    success = nil
                    return
                }
                pendingEncrypted = data
                await decryptPending()
                return
            }

            try await store(data)
        } catch {
            self.error = String(localized: "Échec de l'import : \(error.localizedDescription)")
            self.success = nil
        }
    }

    private func decryptPending() async {
        guard let encrypted = pendingEncrypted else { return }
        decrypting = true
        defer { decrypting = false }
        do {
            let plaintext = try await RcloneCore.shared.decryptEncryptedConfig(
                encrypted,
                password: rclonePassword
            )
            pendingEncrypted = nil
            rclonePassword = ""
            try await store(plaintext)
        } catch {
            self.error = error.localizedDescription
            self.success = nil
        }
    }

    /// Stockage commun : chiffre at-rest via ConfigStore, recharge librclone.
    private func store(_ data: Data) async throws {
        try await ConfigStore.shared.save(data)
        try await ConfigStore.shared.migrateMasterKeyToSharedAccessGroupIfNeeded()
        await RcloneConfigEditor.refreshRuntimeAndNotify()

        success = String(localized: "Configuration importée et chiffrée (\(data.count) octets).")
        error = nil

        // Give the UI a moment to show the success state before dismissing.
        try? await Task.sleep(for: .milliseconds(800))
        onImported()
        dismiss()
    }
}
