//
//  GhostVaultSettingsView.swift
//  Rclone GUI — Views/Settings
//
//  Écran principal de Ghost Vault (RG-16 / RG-3) : sauvegarde chiffrée de
//  toute la configuration rclone dans un remote appartenant à l'utilisateur,
//  scellée par Face ID / Touch ID / mot de passe iCloud. Sans compte.
//
//  On chiffre TOUJOURS côté client, même si le remote cible est déjà chiffré
//  (typiquement un backend `crypt` rclone) — defense in depth.
//

import SwiftUI

struct GhostVaultSettingsView: View {
    @State private var manifest: [GhostVaultDescriptor] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var showRestore = false
    @State private var restoreInitial: GhostVaultDescriptor?
    @State private var toast: AppToast?

    var body: some View {
        Form {
            heroSection
            actionsSection
            vaultsSection
            explainerSection
        }
        .navigationTitle("Ghost Vault")
        #if os(iOS)
        .rgInlineNavTitle()
        #endif
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .ghostVaultDidChange)) { _ in
            Task { await reload() }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CreateVaultView()
            }
        }
        .sheet(isPresented: $showRestore) {
            NavigationStack {
                RestoreVaultView(initial: restoreInitial)
            }
        }
        .appToast($toast)
    }

    // MARK: Sections

    private var heroSection: some View {
        Section {
            AppHeroCard(
                title: "Ghost Vault",
                subtitle: "Sauvegarde chiffrée de ta config dans un de tes remotes, scellée par biométrie.",
                systemImage: "lock.shield.fill",
                tint: .indigo
            ) {
                HStack(spacing: 10) {
                    AppMetricPill(value: "\(manifest.count)", label: "vaults connus", systemImage: "lock.fill", tint: .indigo)
                    AppMetricPill(value: "E2E", label: "chiffré client", systemImage: "key.fill", tint: .green)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                showCreate = true
            } label: {
                GhostVaultNavigationRow(
                    icon: "plus.rectangle.on.folder.fill",
                    title: "Créer un vault",
                    subtitle: "Chiffre et uploade ta config dans un remote",
                    tint: .indigo,
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)

            Button {
                restoreInitial = nil
                showRestore = true
            } label: {
                GhostVaultNavigationRow(
                    icon: "arrow.down.doc.fill",
                    title: "Restaurer un vault",
                    subtitle: "Depuis un remote que tu possèdes",
                    tint: .teal,
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)
        } header: {
            Text("Actions")
        }
    }

    @ViewBuilder
    private var vaultsSection: some View {
        Section {
            if loading {
                HStack {
                    ProgressView()
                    Text("Chargement…").foregroundStyle(.secondary)
                }
            } else if manifest.isEmpty {
                Text("Aucun vault connu sur cet appareil.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(manifest) { descriptor in
                    VaultRow(
                        descriptor: descriptor,
                        onRestore: {
                            restoreInitial = descriptor
                            showRestore = true
                        },
                        onDelete: {
                            Task { await delete(descriptor) }
                        }
                    )
                }
            }
        } header: {
            Text("Vaults connus")
        } footer: {
            Text("Ces vaults ont été créés ou restaurés sur cet appareil. Pour en trouver d'autres sur tes remotes, utilise « Restaurer » → « Scanner un remote ».")
        }
    }

    private var explainerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                row(systemImage: "lock.fill", tint: .indigo, title: "Chiffrement côté client",
                    body: "Ton rclone.conf est chiffré (ChaCha20-Poly1305) avec une clé dérivée de ta passphrase avant de quitter l'app. On chiffre même si le remote cible est déjà un `crypt` rclone.")
                row(systemImage: "faceid", tint: .green, title: "Scellé par biométrie",
                    body: "La création et la restauration demandent Face ID / Touch ID (ou le mot de passe de l'appareil en fallback).")
                row(systemImage: "person.fill.questionmark", tint: .orange, title: "Sans compte",
                    body: "Pas de serveur tiers. Le vault atterrit dans un remote que tu choisis. La passphrase ne quitte jamais l'app.")
                row(systemImage: "iphone.and.arrow.forward", tint: .blue, title: "Portable",
                    body: "La passphrase ouvre le vault sur n'importe quel appareil, indépendamment du Keychain local.")
            }
            .padding(.vertical, 4)
        } header: {
            Text("Comment ça marche")
        }
    }

    private func row(systemImage: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Data

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            manifest = try await GhostVaultService.shared.listLocalManifest()
        } catch {
            manifest = []
        }
    }

    private func delete(_ descriptor: GhostVaultDescriptor) async {
        do {
            try await GhostVaultService.shared.delete(descriptor: descriptor)
            toast = AppToast(title: "Vault supprimé", severity: .success)
        } catch {
            toast = AppToast(title: "Erreur", message: error.localizedDescription, severity: .error)
        }
    }
}

// MARK: - VaultRow

private struct VaultRow: View {
    let descriptor: GhostVaultDescriptor
    let onRestore: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.indigo)
                Text(descriptor.filename)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(formattedSize)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(descriptor.remote)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.12), in: Capsule())
                    .foregroundStyle(.indigo)
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(descriptor.remoteCount) remote\(descriptor.remoteCount > 1 ? "s" : "")")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("•")
                    .foregroundStyle(.secondary)
                Text(descriptor.deviceName)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                Text(formattedDate)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Restaurer", action: onRestore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(role: .destructive, action: onDelete) {
                    Label("Supprimer", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(descriptor.sizeBytes), countStyle: .file)
    }

    private var formattedDate: String {
        descriptor.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - GhostVaultNavigationRow

/// Équivalent local de `SettingsNavigationRow` (qui est `private` dans
/// SettingsView.swift). Même apparence, accessible depuis ce fichier.
struct GhostVaultNavigationRow: View {
    let icon: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var tint: Color = .accentColor
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}