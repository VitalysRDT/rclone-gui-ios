//
//  RcloneInteractiveConfigSession.swift
//  Rclone GUI — Services
//
//  Drives the rclone `config/create` → `config/update` state machine
//  in non-interactive mode. Mirrors `rclone config` CLI faithfully so
//  100% of backends — including wrappers (crypt, alias, union, combine,
//  chunker, compress, hasher, archive) — can be configured manually,
//  even when their schema requires multi-step prompts that the
//  graphical wizard cannot expose statically.
//
//  Flow:
//    1. start(name:type:) → POST config/create with parameters={} and
//       opt={ nonInteractive: true, all: true } so rclone walks ALL
//       options, not only the post-config ones.
//    2. As long as the response carries a non-empty `State` and an
//       `Option`, we expose the prompt to the UI via `current` +
//       `history`. The UI calls `submit(_:)` with the user answer.
//    3. `submit` chooses the right RPC:
//         - `config/password` for `option.isPassword == true` (rclone
//           obscures the password server-side, identical to the CLI),
//         - `config/update` for every other option (continue=true,
//           state=savedState, result=userAnswer).
//    4. Loop until `isComplete` (state empty and option nil).
//    5. `cancel()` removes the half-written remote section so the
//       user can restart cleanly.
//

import Foundation
import Observation

@MainActor
@Observable
final class RcloneInteractiveConfigSession {

    // MARK: - Journal entries

    enum Entry: Identifiable, Hashable {
        case prompt(id: UUID = UUID(), option: RcloneOptionSchema)
        case answer(id: UUID = UUID(), text: String, secret: Bool)
        case info(id: UUID = UUID(), text: String)
        case error(id: UUID = UUID(), text: String)
        case done(id: UUID = UUID())

        var id: UUID {
            switch self {
            case .prompt(let id, _), .answer(let id, _, _),
                 .info(let id, _), .error(let id, _), .done(let id):
                return id
            }
        }
    }

    // MARK: - Observable state

    /// Full chronological history of the session (used by the terminal view).
    var history: [Entry] = []

    /// The pending question rclone is asking. `nil` when busy or done.
    var current: RcloneOptionSchema?

    /// Opaque resumption token returned by rclone alongside each prompt.
    /// Must be forwarded verbatim on the next `config/update` call.
    var state: String?

    /// `true` once rclone confirms the remote section is fully written.
    var isDone: Bool = false

    /// `true` while a network call is in-flight. Disables the input row.
    var isBusy: Bool = false

    /// Remote being created. Captured at `start(...)` time so `cancel()`
    /// can clean up even if the user leaves the view.
    private(set) var remoteName: String = ""
    private(set) var remoteType: String = ""

    /// `true` once we have sent the first `config/create` (rclone has
    /// written at least a stub section to rclone.conf).
    private var didPreCreate: Bool = false

    // MARK: - Public API

    func start(name: String, type: String) async {
        remoteName = name
        remoteType = type
        history.removeAll()
        current = nil
        state = nil
        isDone = false

        appendInfo("rclone config create \(name) \(type)")

        let input = ConfigCreateInput(
            name: name,
            type: type,
            parameters: [:],
            opt: ConfigCreateOpt(nonInteractive: true, all: true)
        )
        await call(method: "config/create", input: input)
    }

    func submit(_ answer: String) async {
        guard let option = current, let savedState = state else {
            appendError("Aucune question en attente.")
            return
        }

        // Record what the user typed (masked if it's a secret).
        history.append(.answer(text: option.isPassword ? maskedSecret(answer) : answer,
                               secret: option.isPassword))

        if option.isPassword {
            // rclone obscures the password server-side. The result we
            // send back over the state machine is the obscured string
            // it returns. After that, `config/update` continues.
            await sendPassword(answer, savedState: savedState)
        } else {
            let input = ConfigCreateInput(
                name: remoteName,
                type: remoteType,
                parameters: [:],
                opt: ConfigCreateOpt(
                    nonInteractive: true,
                    all: true,
                    continue: true,
                    state: savedState,
                    result: answer
                )
            )
            await call(method: "config/update", input: input)
        }
    }

    /// User picked one of `option.examples` — submit its value verbatim.
    func submitExample(_ value: String) async {
        await submit(value)
    }

    func cancel() async {
        guard didPreCreate, !remoteName.isEmpty else { return }
        struct DeleteInput: Encodable { let name: String }
        let body = (try? JSONEncoder().encode(DeleteInput(name: remoteName)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        _ = try? await RcloneCore.shared.rpcRaw("config/delete", body)
        await RcloneCore.shared.invalidateConfigCache()
        await LogService.shared.log(
            .info,
            category: "wizard.interactive",
            message: "Canceled — removed orphan remote \(remoteName)"
        )
    }

    // MARK: - Private helpers

    private func call(method: String, input: ConfigCreateInput) async {
        isBusy = true
        defer { isBusy = false }

        do {
            let response: ConfigCreateResponse = try await RcloneCore.shared.rpc(
                method,
                input: input
            )
            didPreCreate = true
            handle(response: response)
        } catch {
            appendError(error.localizedDescription)
            await LogService.shared.log(
                .error,
                category: "wizard.interactive",
                message: "\(method) failed: \(error.localizedDescription)"
            )
        }
    }

    /// Send the password via the dedicated `config/password` endpoint so
    /// rclone obscures it identically to the native CLI. The endpoint
    /// shares the same response shape (state machine continuation) as
    /// `config/update`.
    private func sendPassword(_ password: String, savedState: String) async {
        isBusy = true
        defer { isBusy = false }

        guard let option = current else { return }

        // config/password expects `parameters` to carry the field name
        // and the raw password. rclone writes the obscured form to the
        // config and then resumes the state machine, returning either
        // the next Option or an empty state.
        let input = ConfigCreateInput(
            name: remoteName,
            type: remoteType,
            parameters: [option.name: password],
            opt: ConfigCreateOpt(
                nonInteractive: true,
                all: true,
                continue: true,
                state: savedState,
                result: password
            )
        )
        do {
            let response: ConfigCreateResponse = try await RcloneCore.shared.rpc(
                "config/password",
                input: input
            )
            handle(response: response)
        } catch {
            // Some rclone builds don't expose `config/password` as a
            // resumption RPC — fall back to obscure-on-create via
            // `config/update` with opt.obscure=true.
            await LogService.shared.log(
                .info,
                category: "wizard.interactive",
                message: "config/password unavailable, falling back to config/update + obscure"
            )
            let fallback = ConfigCreateInput(
                name: remoteName,
                type: remoteType,
                parameters: [:],
                opt: ConfigCreateOpt(
                    nonInteractive: true,
                    all: true,
                    obscure: true,
                    continue: true,
                    state: savedState,
                    result: password
                )
            )
            await call(method: "config/update", input: fallback)
        }
    }

    private func handle(response: ConfigCreateResponse) {
        if let err = response.error, !err.isEmpty {
            appendError(err)
            return
        }
        if response.isComplete {
            state = nil
            current = nil
            isDone = true
            history.append(.done())
            history.append(.info(text: "Remote « \(remoteName) » créé."))
            return
        }
        state = response.state
        current = response.option
        if let opt = response.option {
            history.append(.prompt(option: opt))
        }
    }

    private func appendInfo(_ text: String) {
        history.append(.info(text: text))
    }

    private func appendError(_ text: String) {
        history.append(.error(text: text))
    }

    private func maskedSecret(_ raw: String) -> String {
        String(repeating: "•", count: min(max(raw.count, 1), 12))
    }
}
