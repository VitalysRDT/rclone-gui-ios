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

struct ImportConfigView: View {
    let onImported: () -> Void

    @State private var importing = false
    @State private var error: String?
    @State private var success: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .padding(.top, 40)

                Text("Importer rclone.conf")
                    .font(.title2.bold())

                Text("Choisis le fichier `rclone.conf` que tu utilises sur Mac, Linux, ou ton NAS. Il sera chiffré et stocké localement.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()

                if let success {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }

                Button {
                    importing = true
                } label: {
                    Label("Choisir un fichier", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationTitle("Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
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
        }
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
#else
struct ImportConfigView: View {
    let onImported: () -> Void
    var body: some View {
        Text("Import indisponible sur cette plateforme")
    }
}
#endif
