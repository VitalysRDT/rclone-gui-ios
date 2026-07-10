//
//  ConfigCreateFlow.swift
//  Rclone GUI — Models/Wizard
//
//  Drives `config/create` and the non-interactive state machine that can
//  follow it. Most backends complete in a single call, but some come back
//  with post-config questions — iCloud Drive notably returns `config_2fa`
//  (the two-factor code that unlocks the session cookies + trust token).
//  The graphical wizard used to ignore those questions, so the remote was
//  written without trust token and stayed unusable. This flow surfaces
//  each question through the `ask` callback and resumes rclone with
//  `config/update { continue: true, state, result }` until completion.
//
//  The RPC transport is injected so the machine is unit-testable without
//  librclone.
//

import Foundation

nonisolated enum ConfigCreateFlowError: Error, Equatable, LocalizedError {
    /// rclone asked a question without the state token needed to answer it.
    case malformedContinuation
    /// The user dismissed a question — the caller should clean up the
    /// half-written remote section (config/delete).
    case cancelled
    /// Safety valve: more chained questions than any real backend asks.
    case tooManyQuestions
    /// rclone reported a fatal error while finishing the state machine.
    case rclone(String)

    var errorDescription: String? {
        switch self {
        case .malformedContinuation:
            return String(localized: "Réponse rclone inattendue pendant la configuration.")
        case .cancelled:
            return String(localized: "Configuration annulée — la question rclone est restée sans réponse.")
        case .tooManyQuestions:
            return String(localized: "Trop de questions de configuration successives — abandon.")
        case .rclone(let message):
            return message
        }
    }
}

@MainActor
struct ConfigCreateFlow {

    /// RPC transport (method, input) → response.
    let rpc: (_ method: String, _ input: ConfigCreateInput) async throws -> ConfigCreateResponse

    /// Hard cap on chained questions (config_2fa + eventual ADP approval
    /// stay well below this).
    static let maxQuestions = 8

    /// Runs `config/create` then answers every follow-up question rclone
    /// asks, via `ask`. `ask` receives the option describing the question
    /// plus the soft error rclone attached to the retry (nil on the first
    /// attempt); returning `nil` cancels the flow.
    ///
    /// `onRemoteWritten` fires right after the first successful RPC — from
    /// that point a (possibly partial) section exists in rclone.conf, so
    /// callers can arm their config/delete cleanup path.
    func run(
        name: String,
        type: String,
        parameters: [String: String],
        obscure: Bool,
        onRemoteWritten: () async -> Void = {},
        ask: (_ option: RcloneOptionSchema, _ lastError: String?) async -> String?
    ) async throws {
        var response = try await rpc("config/create", ConfigCreateInput(
            name: name,
            type: type,
            parameters: parameters,
            opt: ConfigCreateOpt(nonInteractive: true, obscure: obscure ? true : nil)
        ))
        await onRemoteWritten()

        var answered = 0
        while !response.isComplete {
            guard let option = response.option,
                  let state = response.state, !state.isEmpty else {
                // A soft error with no follow-up question is fatal.
                if let err = response.error, !err.isEmpty {
                    throw ConfigCreateFlowError.rclone(err)
                }
                throw ConfigCreateFlowError.malformedContinuation
            }
            guard answered < Self.maxQuestions else {
                throw ConfigCreateFlowError.tooManyQuestions
            }
            let softError = (response.error?.isEmpty == false) ? response.error : nil
            guard let answer = await ask(option, softError) else {
                throw ConfigCreateFlowError.cancelled
            }
            answered += 1
            response = try await rpc("config/update", ConfigCreateInput(
                name: name,
                type: type,
                parameters: [:],
                opt: ConfigCreateOpt(
                    nonInteractive: true,
                    obscure: option.isPassword ? true : nil,
                    continue: true,
                    state: state,
                    result: answer
                )
            ))
        }
        if let err = response.error, !err.isEmpty {
            throw ConfigCreateFlowError.rclone(err)
        }
    }
}
