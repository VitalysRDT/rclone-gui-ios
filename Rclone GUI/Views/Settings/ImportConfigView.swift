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

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct ImportConfigView: View {
    let onImported: () -> Void

    @State private var importing = false
    @State private var error: String?
    @State private var success: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    importHeader
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button {
                        importing = true
                    } label: {
                        importSourceRow(
                            icon: "folder.fill",
                            tint: .blue,
                            title: "Depuis Fichiers",
                            subtitle: "rclone.conf"
                        )
                    }
                    .buttonStyle(.plain)

                    importSourceRow(
                        icon: "qrcode",
                        tint: .green,
                        title: "Scanner depuis Mac",
                        subtitle: "rclone config dump | qrencode",
                        disabled: true
                    )

                    importSourceRow(
                        icon: "globe",
                        tint: .indigo,
                        title: "URL / iCloud",
                        subtitle: "Bientôt",
                        disabled: true
                    )
                } header: {
                    Text("Source")
                } footer: {
                    Text("Le fichier sera chiffré et stocké localement. Tes clés ne quittent jamais ton appareil.")
                }

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "lock")
                            .foregroundStyle(.secondary)
                        Text("Mot de passe rclone (optionnel)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Mot de passe rclone")
                } footer: {
                    Text("Si ton rclone.conf est protégé par un mot de passe rclone, il sera demandé à la lecture. Stocké en Keychain et protégé par Face ID.")
                }

                if let success {
                    Section {
                        AppInlineMessage(title: "Configuration importée", message: success, systemImage: "checkmark.circle.fill", tint: .green)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                } else if let error {
                    Section {
                        AppInlineMessage(title: "Import impossible", message: error, systemImage: "exclamationmark.triangle.fill", tint: .red)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("Importer")
            #if os(iOS)
            .rgInlineNavTitle()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            #if os(iOS)
            .sheet(isPresented: $importing) {
                DocumentPicker(
                    contentTypes: Self.allowedContentTypes,
                    allowsMultipleSelection: false,
                    onPicked: { urls in
                        importing = false
                        guard let url = urls.first else { return }
                        Task { await load(url) }
                    },
                    onCancelled: { importing = false }
                )
            }
            #elseif os(macOS)
            .onChange(of: importing) { _, newValue in
                guard newValue else { return }
                importing = false
                presentOpenPanel()
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 560)
        #endif
    }

    #if os(macOS)
    /// macOS : NSOpenPanel restreint au rclone.conf (et variantes). L'URL
    /// retournée est security-scoped (fichier sélectionné par l'utilisateur),
    /// donc load(_:) peut la lire comme sur iOS.
    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = Self.allowedContentTypes
        panel.prompt = String(localized: "Importer")
        if panel.runModal() == .OK, let url = panel.url {
            Task { await load(url) }
        }
    }
    #endif

    private var importHeader: some View {
        HStack(spacing: 14) {
            RGCryptSeal(size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Import rclone.conf")
                    .font(.system(size: 20, weight: .bold))
                Text("Chiffré localement par Face ID + Secure Enclave")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func importSourceRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
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
            try await ConfigStore.shared.save(data)
            try await ConfigStore.shared.migrateMasterKeyToSharedAccessGroupIfNeeded()
            await RcloneConfigEditor.refreshRuntimeAndNotify()

            success = "Configuration importée et chiffrée (\(data.count) octets)."
            error = nil

            // Give the UI a moment to show the success state before dismissing.
            try? await Task.sleep(for: .milliseconds(800))
            onImported()
            dismiss()
        } catch {
            self.error = "Échec de l'import : \(error.localizedDescription)"
            self.success = nil
        }
    }
}

#if canImport(UIKit)
private struct DocumentPicker: UIViewControllerRepresentable {
    let contentTypes: [UTType]
    let allowsMultipleSelection: Bool
    let onPicked: ([URL]) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancelled: onCancelled)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void
        let onCancelled: () -> Void

        init(onPicked: @escaping ([URL]) -> Void, onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPicked(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancelled()
        }
    }
}
#endif
