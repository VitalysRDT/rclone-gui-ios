//
//  MoveSheetView.swift
//  Rclone GUI — Views/Folders
//
//  Lets the user move/copy a remote entry to a different remote and/or
//  path. Two-field form (remote + path) for now; a full destination
//  picker can replace this in v2.
//

import SwiftUI

struct MoveSheetView: View {
    let entry: RemoteEntryDTO
    let sourceRemote: String
    let availableRemotes: [String]
    @Binding var isPresented: Bool

    @State private var dstRemote: String
    @State private var dstPath: String
    @State private var isWorking = false
    @State private var error: String?

    init(
        entry: RemoteEntryDTO,
        sourceRemote: String,
        availableRemotes: [String],
        isPresented: Binding<Bool>
    ) {
        self.entry = entry
        self.sourceRemote = sourceRemote
        self.availableRemotes = availableRemotes
        self._isPresented = isPresented

        // Default destination: same remote, parent of source path,
        // keeping the original filename.
        self._dstRemote = State(initialValue: sourceRemote)
        let parent = (entry.pathInRemote as NSString).deletingLastPathComponent
        let baseName = entry.name
        let initial = parent.isEmpty ? baseName : "\(parent)/\(baseName)"
        self._dstPath = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Source") {
                    LabeledContent("Remote", value: sourceRemote)
                    LabeledContent("Chemin") {
                        Text(entry.pathInRemote.isEmpty ? "/" : entry.pathInRemote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }

                Section("Destination") {
                    Picker("Remote", selection: $dstRemote) {
                        ForEach(availableRemotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    let pathField = TextField(
                        "Chemin de destination",
                        text: $dstPath,
                        prompt: Text("chemin/dans/le/remote/fichier.ext"),
                        axis: .vertical
                    )
                    .labelsHidden()
                    .autocorrectionDisabled(true)
                    .lineLimit(1...3)

                    #if os(iOS)
                    pathField.rgNoAutocap()
                    #else
                    pathField
                    #endif
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if dstRemote == sourceRemote && dstPath == entry.pathInRemote {
                    Section {
                        Label("La destination est identique à la source.",
                              systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Déplacer")
            #if os(iOS)
            .rgInlineNavTitle()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await performMove() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Déplacer") }
                    }
                    .disabled(!isFormValid || isWorking)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !dstPath.isEmpty
            && !(dstRemote == sourceRemote && dstPath == entry.pathInRemote)
    }

    @MainActor
    private func performMove() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await TransferQueue.shared.enqueueMove(
                srcRemote: sourceRemote,
                srcPath: entry.pathInRemote,
                dstRemote: dstRemote,
                dstPath: dstPath
            )
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "Déplacement enqueued : \(sourceRemote):\(entry.pathInRemote) → \(dstRemote):\(dstPath)"
            )
            isPresented = false
        } catch {
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec déplacement \(sourceRemote):\(entry.pathInRemote) → \(dstRemote):\(dstPath) : \(error.localizedDescription)"
            )
            self.error = error.localizedDescription
        }
    }
}

struct RemoteBatchTransferSheet: View {
    let sourceRemote: String
    let sourcePath: String
    let entries: [RemoteEntryDTO]
    let availableRemotes: [String]
    @Binding var isPresented: Bool

    @State private var kind: TransferKind
    @State private var dstRemote: String
    @State private var dstFolder: String
    @State private var isWorking = false
    @State private var error: String?

    init(
        sourceRemote: String,
        sourcePath: String,
        entries: [RemoteEntryDTO],
        initialKind: TransferKind,
        availableRemotes: [String],
        isPresented: Binding<Bool>
    ) {
        self.sourceRemote = sourceRemote
        self.sourcePath = sourcePath
        self.entries = entries
        self.availableRemotes = availableRemotes.isEmpty ? [sourceRemote] : availableRemotes
        self._isPresented = isPresented
        self._kind = State(initialValue: initialKind)
        self._dstRemote = State(initialValue: sourceRemote)
        self._dstFolder = State(initialValue: sourcePath)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Opération") {
                    Picker("Action", selection: $kind) {
                        Text("Copier").tag(TransferKind.copy)
                        Text("Déplacer").tag(TransferKind.move)
                        Text("Sync").tag(TransferKind.sync)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Source") {
                    LabeledContent("Remote", value: sourceRemote)
                    LabeledContent("Dossier") {
                        Text(sourcePath.isEmpty ? "/" : sourcePath)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Sélection", value: "\(entries.count) élément\(entries.count > 1 ? "s" : "")")
                }

                Section {
                    Picker("Remote", selection: $dstRemote) {
                        ForEach(remoteOptions, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }

                    let field = TextField("Dossier cible", text: $dstFolder, prompt: Text("dossier/cible"), axis: .vertical)
                        .labelsHidden()
                        .autocorrectionDisabled(true)
                        .lineLimit(1...3)

                    #if os(iOS)
                    field.rgNoAutocap()
                    #else
                    field
                    #endif
                } header: {
                    Text("Destination")
                } footer: {
                    Text("Chaque élément garde son nom et sera placé dans le dossier cible.")
                }

                if kind == .sync {
                    Section {
                        Label(
                            "Sync miroir les dossiers sélectionnés : les fichiers présents uniquement dans le dossier cible peuvent être supprimés par rclone.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section("Éléments") {
                    ForEach(entries.prefix(12)) { entry in
                        Label(entry.name, systemImage: entry.isDirectory ? "folder" : "doc")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if entries.count > 12 {
                        Text("+ \(entries.count - 12) autre\(entries.count - 12 > 1 ? "s" : "")")
                            .foregroundStyle(.secondary)
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(operationTitle)
            #if os(iOS)
            .rgInlineNavTitle()
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await enqueue() }
                    } label: {
                        if isWorking { ProgressView() } else { Text("Ajouter") }
                    }
                    .disabled(!isFormValid || isWorking)
                }
            }
        }
    }

    private var remoteOptions: [String] {
        if availableRemotes.contains(dstRemote) {
            return availableRemotes
        }
        return [dstRemote] + availableRemotes
    }

    private var operationTitle: String {
        switch kind {
        case .copy: return String(localized: "Copier")
        case .move: return String(localized: "Déplacer")
        case .sync: return String(localized: "Synchroniser")
        default: return String(localized: "Transférer")
        }
    }

    private var isFormValid: Bool {
        !entries.isEmpty && !(dstRemote == sourceRemote && clean(dstFolder) == clean(sourcePath))
    }

    @MainActor
    private func enqueue() async {
        isWorking = true
        defer { isWorking = false }

        do {
            try await TransferQueue.shared.enqueueRemoteTransferBatch(
                kind: kind,
                srcRemote: sourceRemote,
                entries: entries,
                dstRemote: dstRemote,
                dstFolder: clean(dstFolder)
            )
            await LogService.shared.log(
                .info,
                category: "transfer",
                message: "\(operationTitle) remote batch ajouté : \(entries.count) élément(s) \(sourceRemote):\(sourcePath) → \(dstRemote):\(clean(dstFolder))"
            )
            isPresented = false
        } catch {
            await LogService.shared.log(
                .error,
                category: "transfer",
                message: "Échec batch remote \(kind.rawValue) : \(error.localizedDescription)"
            )
            self.error = error.localizedDescription
        }
    }

    private func clean(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
