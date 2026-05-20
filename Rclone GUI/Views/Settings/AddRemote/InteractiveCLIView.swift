//
//  InteractiveCLIView.swift
//  Rclone GUI — Views/Settings/AddRemote
//
//  Terminal-style screen that runs the full rclone `config create`
//  state machine end-to-end. Used as an alternative path to the
//  graphical wizard so backends whose schemas need multi-step prompts
//  (crypt, alias, union, combine, chunker, archive, …) can still be
//  configured manually from iOS — just like `rclone config` on a
//  desktop.
//
//  Look:
//    - Monospace font, dark background.
//    - Scrollable journal: prompts (white), user answers (green), info
//      (yellow), errors (red).
//    - Examples (when option.exclusive) shown as tappable chips above
//      the input row.
//    - SecureField for `isPassword`, plain TextField otherwise.
//

import SwiftUI

struct InteractiveCLIView: View {

    @Bindable var state: WizardState
    let onCreated: () -> Void

    @State private var session = RcloneInteractiveConfigSession()
    @State private var input: String = ""
    @State private var hasStarted = false
    @State private var isFinalizing = false

    private let palette = TerminalPalette()

    var body: some View {
        VStack(spacing: 0) {
            journal
            inputBar
        }
        .background(palette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if session.isDone {
                    Button("Terminer") { Task { await finalize() } }
                        .disabled(isFinalizing)
                }
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            guard let backend = state.selectedBackend else { return }
            await session.start(name: state.name, type: backend.name)
            // The session's didPreCreate flag mirrors what the wizard
            // already tracks for cancellation cleanup.
            state.remoteWasPreCreated = true
        }
    }

    // MARK: - Journal

    private var journal: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(session.history) { entry in
                        entryView(for: entry)
                            .id(entry.id)
                    }
                    if session.isBusy {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(palette.dimText)
                            Text("rclone réfléchit…")
                                .foregroundStyle(palette.dimText)
                        }
                        .font(.system(.footnote, design: .monospaced))
                        .padding(.top, 4)
                    }
                    Color.clear.frame(height: 12).id("BOTTOM")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.history.count) { _, _ in
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func entryView(for entry: RcloneInteractiveConfigSession.Entry) -> some View {
        switch entry {
        case .info(_, let text):
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.infoText)
        case .error(_, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("✗")
                Text(text)
            }
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(palette.errorText)
        case .prompt(_, let option):
            promptView(option)
        case .answer(_, let text, _):
            HStack(alignment: .top, spacing: 6) {
                Text(">")
                    .foregroundStyle(palette.dimText)
                Text(text)
                    .foregroundStyle(palette.answerText)
            }
            .font(.system(.body, design: .monospaced))
        case .done:
            Text("✓ Configuration terminée")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .foregroundStyle(palette.successText)
        }
    }

    private func promptView(_ option: RcloneOptionSchema) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("[\(option.name)]")
                .font(.system(.footnote, design: .monospaced).weight(.semibold))
                .foregroundStyle(palette.dimText)
            if !option.help.isEmpty {
                Text(option.help)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(palette.promptText)
                    .textSelection(.enabled)
            }
            if !option.defaultStr.isEmpty {
                Text("défaut : \(option.defaultStr)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(palette.dimText)
            }
        }
    }

    // MARK: - Input row

    @ViewBuilder
    private var inputBar: some View {
        if session.isDone {
            doneBanner
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let option = session.current, let examples = option.examples, !examples.isEmpty {
                    examplesRow(examples)
                }
                HStack(spacing: 8) {
                    Text("$")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(palette.dimText)
                    inputField
                    sendButton
                }
                .padding(10)
                .background(palette.inputBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(12)
            .background(palette.bottomBar)
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if session.current?.isPassword == true {
            SecureField("mot de passe", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(palette.answerText)
                .font(.system(.body, design: .monospaced))
                .submitLabel(.send)
                .onSubmit(send)
        } else {
            TextField("réponse", text: $input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard(for: session.current))
                .foregroundStyle(palette.answerText)
                .font(.system(.body, design: .monospaced))
                .submitLabel(.send)
                .onSubmit(send)
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Image(systemName: "paperplane.fill")
                .foregroundStyle(canSend ? palette.successText : palette.dimText)
        }
        .disabled(!canSend)
        .buttonStyle(.plain)
    }

    private func examplesRow(_ examples: [RcloneExampleValue]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(examples, id: \.value) { ex in
                    Button {
                        Task { await session.submitExample(ex.value) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.value)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                            if !ex.help.isEmpty {
                                Text(ex.help)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(palette.dimText)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(palette.chipBackground, in: Capsule())
                        .foregroundStyle(palette.promptText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var doneBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(palette.successText)
            Text("Remote prêt — appuyer sur « Terminer » pour finaliser.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(palette.promptText)
            Spacer()
            if isFinalizing {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .background(palette.bottomBar)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty
            && !session.isBusy
            && session.current != nil
    }

    private func send() {
        let payload = input
        guard !payload.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        input = ""
        Task { await session.submit(payload) }
    }

    private func keyboard(for option: RcloneOptionSchema?) -> UIKeyboardType {
        guard let option else { return .default }
        switch option.type.lowercased() {
        case "int", "uint", "uint32", "uint64", "duration": return .numbersAndPunctuation
        case "string":
            if option.name.contains("url") || option.name.contains("endpoint") {
                return .URL
            }
            if option.name.contains("email") || option.name.contains("user") {
                return .emailAddress
            }
            return .default
        default:
            return .default
        }
    }

    private func finalize() async {
        guard session.isDone else { return }
        isFinalizing = true
        defer { isFinalizing = false }
        await RcloneConfigEditor.refreshRuntimeAndNotify()
        await LogService.shared.log(
            .info,
            category: "wizard.interactive",
            message: "Remote « \(state.name) » créé via mode CLI"
        )
        onCreated()
    }
}

// MARK: - Palette

private struct TerminalPalette {
    let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    let bottomBar = Color(red: 0.09, green: 0.10, blue: 0.13)
    let inputBackground = Color(red: 0.13, green: 0.14, blue: 0.18)
    let chipBackground = Color(red: 0.16, green: 0.18, blue: 0.22)
    let promptText = Color.white
    let answerText = Color(red: 0.45, green: 0.94, blue: 0.55)
    let dimText = Color(white: 0.55)
    let infoText = Color(red: 0.98, green: 0.85, blue: 0.40)
    let errorText = Color(red: 1.0, green: 0.40, blue: 0.40)
    let successText = Color(red: 0.45, green: 0.94, blue: 0.55)
}
