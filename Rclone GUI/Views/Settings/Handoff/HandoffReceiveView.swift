//
//  HandoffReceiveView.swift
//  Rclone GUI — Views/Settings/Handoff
//
//  Wizard « Handoff P2P — recevoir ». Quatre étapes :
//   1. Choisir la source (Scanner QR, Fichier .rclonebackup, Presse-papiers).
//   2. Taper les 6 mots de la passphrase.
//   3. Aperçu de ce qui est sur le point d'être importé ; si une config
//      locale existe → écran conflit (Remplacer / Fusionner / Annuler).
//   4. Application finale (gated par FaceID).
//

import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#endif

struct HandoffReceiveView: View {
    @Environment(\.dismiss) private var dismiss

    /// Payload HND1: déjà extrait (fichier .rclonebackup reçu par
    /// AirDrop / Fichiers via onOpenURL) : on saute l'étape « source »
    /// et on passe directement à la passphrase.
    var prefilledPayload: String?

    @State private var step: Step = .source
    @State private var sourceKind: SourceKind = .qr
    @State private var payload: String = ""
    @State private var passphraseWords: [String] = ["", "", "", "", "", ""]
    @State private var passphraseLanguage: HandoffPassphraseLanguage = .french
    @State private var preview: HandoffReceivedEnvelope?
    @State private var mergePlan: HandoffMergePlan?
    @State private var strategy: HandoffImportStrategy = .merge
    @State private var importing = false
    @State private var importResult: HandoffApplyResult?
    @State private var error: String?
    @State private var showFilePicker = false
    @State private var showQRScanner = false
    @State private var toast: AppToast?

    enum Step: Equatable {
        case source
        case passphrase
        case preview
        case done
    }

    enum SourceKind: String, CaseIterable {
        case qr
        case file
        case clipboard

        var systemImage: String {
            switch self {
            case .qr: return "qrcode.viewfinder"
            case .file: return "folder.fill"
            case .clipboard: return "doc.on.clipboard"
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .qr: return "Scanner un QR"
            case .file: return "Depuis Fichiers"
            case .clipboard: return "Coller le payload"
            }
        }

        var subtitle: LocalizedStringKey {
            switch self {
            case .qr: return "Utilise la caméra de cet appareil"
            case .file: return "Sélectionne un fichier .rclonebackup"
            case .clipboard: return "Colle un payload HND1:"
            }
        }
    }

    var body: some View {
        Form {
            switch step {
            case .source:
                sourceSection
            case .passphrase:
                passphraseSection
            case .preview:
                previewSection
            case .done:
                doneSection
            }

            if let error {
                Section {
                    AppInlineMessage(
                        title: "Erreur",
                        message: LocalizedStringKey(error),
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .red
                    )
                }
            }
        }
        .navigationTitle("Recevoir")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler") { dismiss() }
                    .disabled(importing)
            }
        }
        .sheet(isPresented: $showFilePicker) {
            FilePicker(
                allowedContentTypes: Self.allowedContentTypes,
                onPick: { url in
                    showFilePicker = false
                    ingestFromFile(url: url)
                },
                onCancel: { showFilePicker = false }
            )
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showQRScanner) {
            QRScannerSheet(onScan: { value in
                showQRScanner = false
                payload = value
                Task { await inspect() }
            }, onCancel: {
                showQRScanner = false
            })
        }
        #endif
        .appToast($toast)
        .task {
            if let prefilledPayload, payload.isEmpty, step == .source {
                payload = prefilledPayload
                await inspect()
            }
        }
    }

    // MARK: Sections

    private var sourceSection: some View {
        Group {
            Section {
                AppHeroCard(
                    title: "Importer une config chiffrée",
                    subtitle: "Choisis d'abord comment l'autre appareil t'a fait passer le payload chiffré. La passphrase reste à taper à part.",
                    systemImage: "arrow.down.doc.fill",
                    tint: .blue
                ) {
                    EmptyView()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(SourceKind.allCases, id: \.self) { kind in
                    Button {
                        selectSource(kind)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.systemImage)
                                .foregroundStyle(.blue)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(kind.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Source du payload")
            }

            Section {
                TextEditor(text: $payload)
                    .frame(minHeight: 100)
                    .font(.system(size: 12, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .overlay {
                        if payload.isEmpty {
                            VStack {
                                Spacer()
                                Text("Colle ici le payload commençant par HND1:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }.padding(.horizontal, 8).allowsHitTesting(false)
                        }
                    }
                    .onChange(of: payload) { _, newValue in
                        if let extracted = HandoffEnvelope.extract(from: newValue) {
                            payload = extracted
                        }
                    }
                Button {
                    Task { await inspect() }
                } label: {
                    Label("Utiliser ce payload", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(payload.isEmpty)
            } header: {
                Text("Ou colle directement")
            } footer: {
                Text("Colle le payload complet (commence toujours par « HND1: »). Si tu as entouré d'autre texte, on extrait le payload automatiquement.")
            }
        }
    }

    private var passphraseSection: some View {
        Section {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { idx in
                    HStack(spacing: 10) {
                        Text("\(idx + 1).")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, alignment: .trailing)
                        TextField("Mot \(idx + 1)", text: bindingForWord(at: idx))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.rgGroupedRowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .padding(.vertical, 4)
            Button {
                Task { await unseal() }
            } label: {
                Label("Déchiffrer", systemImage: "lock.open.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!allWordsFilled || importing)
        } header: {
            Text("Passphrase de 6 mots")
        } footer: {
            Text("L'autre personne a lu ces mots sur son écran. Tape-les tels quels, dans l'ordre, sans accent.")
        }
    }

    private var previewSection: some View {
        Group {
            if let preview {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.stack.fill")
                                .foregroundStyle(.blue)
                            Text("\(preview.meta.remoteCount) remote\(preview.meta.remoteCount > 1 ? "s" : "")")
                                .font(.headline)
                            Spacer()
                            Text(QRPayloadBuilder.formattedByteCount(preview.meta.sizeBytes))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if let device = preview.meta.deviceName.nilIfEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "iphone.gen3")
                                    .foregroundStyle(.tertiary)
                                Text("Envoyé par \(device)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(preview.meta.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                } header: {
                    Text("Aperçu du payload")
                }

                conflictSection(preview: preview)
            }

            if !importing {
                Section {
                    Button {
                        Task { await runApply() }
                    } label: {
                        Label(applyLabel, systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(importing || preview == nil)
                }
            } else {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("FaceID puis application…").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var doneSection: some View {
        Section {
            if let importResult {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Configuration importée", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("\(importResult.appliedCount) remote(s) dans ta configuration.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let url = importResult.snapshotURL {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sauvegarde de l'ancienne config :")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Text("Si quelque chose ne va pas, le service client peut te restaurer.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
                Button("Terminé") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func conflictSection(preview: HandoffReceivedEnvelope) -> some View {
        Section {
            if let plan = mergePlan {
                ForEach(plan.addedRemotes, id: \.self) { name in
                    Label(name, systemImage: "plus.circle.fill")
                        .foregroundStyle(.green)
                }
                if !plan.conflictingRemotes.isEmpty {
                    DisclosureGroup("Conflits (\(plan.conflictingRemotes.count))") {
                        ForEach(plan.conflictingRemotes, id: \.name) { entry in
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.name).font(.subheadline.weight(.semibold))
                                    Text("Local (\(entry.localType)) ↔ Entrant (\(entry.incomingType)) — on garde le local")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Picker("Stratégie", selection: $strategy) {
                ForEach([HandoffImportStrategy.replace, .merge, .cancel], id: \.self) { s in
                    Text(s.localizedTitle).tag(s)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Conflit avec ta config locale")
        } footer: {
            switch strategy {
            case .replace:
                Text("Ton rclone.conf actuel sera sauvegardé localement avant d'être écrasé.")
            case .merge:
                Text("Les remotes manquants sont ajoutés. En cas de collision (même nom), on garde la version locale pour préserver tes tokens OAuth.")
            case .cancel:
                Text("Aucune écriture — tu restes sur l'écran d'aperçu.")
            }
        }
    }

    // MARK: Actions

    private func selectSource(_ kind: SourceKind) {
        sourceKind = kind
        switch kind {
        case .qr:
            #if os(iOS)
            showQRScanner = true
            #else
            error = "Le scan caméra n'est disponible que sur iOS. Sur Mac, colle le payload ou choisis un fichier .rclonebackup."
            #endif
        case .file:
            showFilePicker = true
        case .clipboard:
            if let text = UIPasteboard.general.string, let extracted = HandoffEnvelope.extract(from: text) {
                payload = extracted
                Task { await inspect() }
            } else {
                error = "Le presse-papiers ne contient pas de payload HND1: valide."
            }
        }
    }

    private func ingestFromFile(url: URL) {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            if let text = String(data: data, encoding: .utf8),
               let extracted = HandoffEnvelope.extract(from: text) {
                payload = extracted
                Task { await inspect() }
            } else {
                error = "Le fichier .rclonebackup ne contient pas un payload HND1: valide."
            }
        } catch {
            self.error = "Échec de lecture : \(error.localizedDescription)"
        }
    }

    private func inspect() async {
        error = nil
        do {
            let envelope = try await HandoffReceiveService.shared.inspect(payload: payload)
            self.preview = envelope
            if let localRaw = try? await ConfigStore.shared.load() {
                let plan = await HandoffReceiveService.shared.buildMergePlan(
                    local: localRaw ?? Data(),
                    incoming: Data() // can't read sealed content without passphrase yet
                )
                self.mergePlan = plan
            }
            self.step = .passphrase
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func unseal() async {
        error = nil
        let nonEmpty = passphraseWords.map { $0.trimmingCharacters(in: .whitespaces) }
        guard nonEmpty.count == 6, nonEmpty.allSatisfy({ !$0.isEmpty }) else {
            error = "Les 6 mots doivent être remplis."
            return
        }
        do {
            let opened = try await HandoffReceiveService.shared.unseal(
                payload: payload,
                passphraseWords: passphraseWords.map { $0.trimmingCharacters(in: .whitespaces) },
                language: passphraseLanguage
            )
            if let localRaw = try? await ConfigStore.shared.load() {
                let plan = await HandoffReceiveService.shared.buildMergePlan(
                    local: localRaw ?? Data(),
                    incoming: opened.rcloneConf
                )
                self.mergePlan = plan
            }
            self.step = .preview
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func runApply() async {
        guard strategy != .cancel else {
            step = .source
            return
        }
        importing = true
        defer { importing = false }
        do {
            let result = try await HandoffReceiveService.shared.apply(
                strategy: strategy,
                payload: payload,
                passphraseWords: passphraseWords.map { $0.trimmingCharacters(in: .whitespaces) },
                language: passphraseLanguage
            )
            self.importResult = result
            self.step = .done
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    // MARK: helpers

    private func bindingForWord(at idx: Int) -> Binding<String> {
        Binding(
            get: { passphraseWords[idx] },
            set: { passphraseWords[idx] = $0.lowercased() }
        )
    }

    private var allWordsFilled: Bool {
        passphraseWords.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var applyLabel: LocalizedStringKey {
        switch strategy {
        case .replace: return "Remplacer ma config"
        case .merge: return "Fusionner"
        case .cancel: return "Annuler"
        }
    }

    private static let allowedContentTypes: [UTType] = [
        .data,
        UTType(filenameExtension: "rclonebackup") ?? .data,
        .plainText,
        .text,
        UTType(filenameExtension: "conf") ?? .data,
    ]
}

// MARK: - String helpers

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
