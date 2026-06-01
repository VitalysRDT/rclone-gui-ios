//
//  LocalDirectoryPicker.swift
//  Rclone GUI — Views/Files
//
//  UIDocumentPicker wrapper for choosing a local destination folder.
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

struct LocalDirectoryPicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void
    let onCancelled: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked, onCancelled: onCancelled)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: (URL) -> Void
        let onCancelled: () -> Void

        init(onPicked: @escaping (URL) -> Void, onCancelled: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onCancelled = onCancelled
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancelled()
                return
            }
            onPicked(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancelled()
        }
    }
}
#elseif canImport(AppKit)
import AppKit

// macOS : NSOpenPanel restreint à la sélection de dossiers. L'URL retournée par
// le panel est automatiquement security-scoped (fichier sélectionné par
// l'utilisateur), donc startAccessingSecurityScopedResource() côté appelant
// fonctionne comme sur iOS. On garde l'API onPicked/onCancelled identique pour
// ne pas toucher au call site (présenté via .sheet dans FolderView).
struct LocalDirectoryPicker: View {
    let onPicked: (URL) -> Void
    let onCancelled: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                // Différé d'un tour de runloop pour laisser la sheet se poser
                // avant d'ouvrir le panel modal.
                DispatchQueue.main.async {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = String(localized: "Choisir")
                    if panel.runModal() == .OK, let url = panel.url {
                        onPicked(url)
                    } else {
                        onCancelled()
                    }
                }
            }
    }
}
#else
struct LocalDirectoryPicker: View {
    let onPicked: (URL) -> Void
    let onCancelled: () -> Void
    var body: some View { Text("Selection de dossier indisponible") }
}
#endif
