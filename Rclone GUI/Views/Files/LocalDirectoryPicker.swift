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
#else
struct LocalDirectoryPicker: View {
    let onPicked: (URL) -> Void
    let onCancelled: () -> Void
    var body: some View { Text("Selection de dossier indisponible") }
}
#endif
