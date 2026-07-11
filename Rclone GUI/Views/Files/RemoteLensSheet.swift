//
//  RemoteLensSheet.swift
//  Rclone GUI — Views/Files
//
//  Feuille d'aperçu « Remote Lens » : vignette / 1re page en tête, puis les
//  métadonnées (EXIF pour les images, pages pour les PDF), obtenues en lisant
//  seulement les octets nécessaires (RemoteLensService, range requests).
//

import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct RemoteLensSheet: View {
    let remote: String
    let entry: RemoteEntryDTO

    @Environment(\.dismiss) private var dismiss
    @State private var preview: RemoteLensPreview?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Analyse de l'aperçu…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let preview {
                    content(preview)
                } else {
                    ContentUnavailableView(
                        "Aperçu indisponible",
                        systemImage: "eye.slash",
                        description: Text("Impossible de lire un aperçu de ce fichier.")
                    )
                }
            }
            .navigationTitle(entry.name)
            .rgInlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .task(id: entry.id) {
            isLoading = true
            preview = await RemoteLensService.shared.preview(for: entry, remote: remote)
            isLoading = false
        }
    }

    @ViewBuilder
    private func content(_ preview: RemoteLensPreview) -> some View {
        Form {
            Section {
                thumbnail(preview)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }

            if let note = preview.note {
                Section {
                    Label(note, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let image = preview.image, !image.isEmpty {
                imageMetadataSection(image)
            }
            if let pdf = preview.pdf {
                pdfMetadataSection(pdf)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ preview: RemoteLensPreview) -> some View {
        if let box = preview.thumbnail {
            RemoteLensImage(cgImage: box.image)
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.vertical, 4)
        } else {
            Image(systemName: preview.kind == .pdf ? "doc.richtext" : "photo")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(height: 160)
        }
    }

    private func imageMetadataSection(_ m: RemoteImageMetadata) -> some View {
        Section("Informations image") {
            if let w = m.pixelWidth, let h = m.pixelHeight {
                row("Dimensions", "\(w) × \(h) px")
            }
            if let make = m.cameraMake, let model = m.cameraModel {
                row("Appareil", "\(make) \(model)")
            } else if let model = m.cameraModel {
                row("Appareil", model)
            }
            if let lens = m.lensModel { row("Objectif", lens) }
            if let date = m.captureDate { row("Prise le", Self.dateFormatter.string(from: date)) }
            if let exp = m.exposure { row("Exposition", exp) }
            if let f = m.fNumber { row("Ouverture", f) }
            if let iso = m.iso { row("Sensibilité", iso) }
            if let focal = m.focalLength { row("Focale", focal) }
            if let lat = m.latitude, let lon = m.longitude {
                row("Position", RemoteLensPlan.formatCoordinate(lat: lat, lon: lon))
            }
        }
    }

    private func pdfMetadataSection(_ m: RemotePDFMetadata) -> some View {
        Section("Informations PDF") {
            if let count = m.pageCount {
                row("Pages", "\(count)")
            }
            if let title = m.title { row("Titre", title) }
            if let author = m.author { row("Auteur", author) }
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}

/// Image cross-platform depuis un CGImage (UIImage / NSImage).
struct RemoteLensImage: View {
    let cgImage: CGImage

    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: UIImage(cgImage: cgImage))
            .resizable()
        #elseif canImport(AppKit)
        Image(nsImage: NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height)))
            .resizable()
        #else
        Image(systemName: "photo").resizable()
        #endif
    }
}
