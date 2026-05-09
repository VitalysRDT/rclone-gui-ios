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
                        "chemin/dans/le/remote/fichier.ext",
                        text: $dstPath,
                        axis: .vertical
                    )
                    .autocorrectionDisabled(true)
                    .lineLimit(1...3)

                    #if os(iOS)
                    pathField.textInputAutocapitalization(.never)
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
            .navigationBarTitleDisplayMode(.inline)
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
