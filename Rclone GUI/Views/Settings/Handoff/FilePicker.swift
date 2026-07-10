//
//  FilePicker.swift
//  Rclone GUI — Views/Settings/Handoff
//
//  UIDocumentPickerViewController wrapper. Used by HandoffReceiveView to
//  pick a `.rclonebackup` file (or any file containing an HND1: payload).
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit

struct FilePicker: UIViewControllerRepresentable {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: FilePicker
        init(_ parent: FilePicker) {
            self.parent = parent
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first {
                parent.onPick(url)
            }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

#else

// macOS fallback — NSOpenPanel via swiftui (no equivalent DocumentPicker).
// For now we route macOS users through the paste-payload path; the
// file picker is iOS-only.

struct FilePicker: View {
    let allowedContentTypes: [UTType]
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Sélecteur de fichier indisponible sur Mac")
                .font(.headline)
            Text("Sur macOS, colle le payload ou choisis Restaurer un vault pour un .rclonebackup distant.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("OK") { onCancel() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .onAppear { onCancel() }
    }
}

#endif
