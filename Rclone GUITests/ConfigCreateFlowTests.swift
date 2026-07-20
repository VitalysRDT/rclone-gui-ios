//
//  ConfigCreateFlowTests.swift
//  Rclone GUITests
//
//  Unit tests for ConfigCreateFlow — the non-interactive state machine
//  behind config/create. Covers the iCloud Drive `config_2fa` follow-up
//  question (answer, retry-on-wrong-code, cancel), the pass-through of
//  obscure flags, and the safety valves (malformed continuation, question
//  storm). The RPC transport is scripted so no librclone is involved.
//

import Testing
import Foundation
@testable import Rclone_GUI

// MARK: - Scripted RPC transport

private actor ScriptedRPC {
    struct Call: Sendable {
        let method: String
        let input: ConfigCreateInput
    }

    private(set) var calls: [Call] = []
    private var script: [ConfigCreateResponse]

    init(script: [ConfigCreateResponse]) {
        self.script = script
    }

    func invoke(_ method: String, _ input: ConfigCreateInput) throws -> ConfigCreateResponse {
        calls.append(Call(method: method, input: input))
        guard !script.isEmpty else {
            throw ConfigCreateFlowError.rclone("script exhausted")
        }
        return script.removeFirst()
    }
}

private actor AskRecorder {
    struct Question: Sendable {
        let name: String
        let lastError: String?
    }

    private(set) var questions: [Question] = []
    private var answers: [String?]

    init(answers: [String?]) {
        self.answers = answers
    }

    func answer(_ option: RcloneOptionSchema, _ lastError: String?) -> String? {
        questions.append(Question(name: option.name, lastError: lastError))
        guard !answers.isEmpty else { return nil }
        return answers.removeFirst()
    }
}

// MARK: - Fixtures

@MainActor
private func makeOption(name: String, help: String = "", isPassword: Bool = false) -> RcloneOptionSchema {
    RcloneOptionSchema(
        name: name,
        help: help,
        type: "string",
        defaultStr: "",
        valueStr: nil,
        required: true,
        isPassword: isPassword,
        sensitive: false,
        advanced: false,
        exclusive: false,
        hide: 0,
        noPrefix: false,
        examples: nil,
        provider: nil
    )
}

@MainActor
private let doneResponse = ConfigCreateResponse(state: nil, option: nil, error: nil)

@MainActor
private func questionResponse(
    _ name: String,
    state: String,
    error: String? = nil,
    isPassword: Bool = false
) -> ConfigCreateResponse {
    ConfigCreateResponse(state: state, option: makeOption(name: name, isPassword: isPassword), error: error)
}

@MainActor
private func makeFlow(_ rpc: ScriptedRPC) -> ConfigCreateFlow {
    ConfigCreateFlow(rpc: { method, input in
        try await rpc.invoke(method, input)
    })
}

// MARK: - Tests

@Suite("ConfigCreateFlow state machine")
@MainActor
struct ConfigCreateFlowTests {

    @Test("Backend sans question : un seul config/create, pas de prompt")
    func completesInOneCall() async throws {
        let rpc = ScriptedRPC(script: [doneResponse])
        let asks = AskRecorder(answers: [])

        try await makeFlow(rpc).run(
            name: "b2", type: "b2",
            parameters: ["account": "x", "key": "y"],
            obscure: false,
            ask: { option, lastError in await asks.answer(option, lastError) }
        )

        let calls = await rpc.calls
        #expect(calls.count == 1)
        #expect(calls[0].method == "config/create")
        #expect(calls[0].input.parameters["account"] == "x")
        #expect(calls[0].input.opt?.nonInteractive == true)
        #expect(calls[0].input.opt?.obscure == nil)
        #expect(await asks.questions.isEmpty)
    }

    @Test("Existing remote starts with config/update")
    func updatesExistingRemote() async throws {
        let rpc = ScriptedRPC(script: [doneResponse])
        let asks = AskRecorder(answers: [])

        try await makeFlow(rpc).run(
            name: "drive", type: "drive",
            parameters: ["scope": "drive"],
            obscure: false,
            initialMethod: "config/update",
            ask: { option, lastError in await asks.answer(option, lastError) }
        )

        let calls = await rpc.calls
        #expect(calls.count == 1)
        #expect(calls[0].method == "config/update")
        #expect(calls[0].input.name == "drive")
        #expect(calls[0].input.parameters["scope"] == "drive")
    }

    @Test("iCloud Drive : question config_2fa répondue via config/update continue")
    func answersTwoFactorQuestion() async throws {
        let rpc = ScriptedRPC(script: [
            questionResponse("config_2fa", state: "*postconfig-2fa"),
            doneResponse
        ])
        let asks = AskRecorder(answers: ["123456"])

        try await makeFlow(rpc).run(
            name: "icloud", type: "iclouddrive",
            parameters: ["apple_id": "user@example.com", "password": "secret"],
            obscure: true,
            ask: { option, lastError in await asks.answer(option, lastError) }
        )

        let calls = await rpc.calls
        #expect(calls.count == 2)
        #expect(calls[0].method == "config/create")
        #expect(calls[0].input.opt?.obscure == true)
        #expect(calls[1].method == "config/update")
        #expect(calls[1].input.opt?.continue == true)
        #expect(calls[1].input.opt?.state == "*postconfig-2fa")
        #expect(calls[1].input.opt?.result == "123456")
        // config_2fa n'est pas un champ password → pas d'obscure sur la relance.
        #expect(calls[1].input.opt?.obscure == nil)

        let questions = await asks.questions
        #expect(questions.count == 1)
        #expect(questions[0].name == "config_2fa")
        #expect(questions[0].lastError == nil)
    }

    @Test("Question de type password : obscure=true sur la continuation")
    func obscuresPasswordAnswers() async throws {
        let rpc = ScriptedRPC(script: [
            questionResponse("password", state: "*ask-pass", isPassword: true),
            doneResponse
        ])
        let asks = AskRecorder(answers: ["hunter2"])

        try await makeFlow(rpc).run(
            name: "r", type: "sftp", parameters: [:], obscure: false,
            ask: { option, lastError in await asks.answer(option, lastError) }
        )

        let calls = await rpc.calls
        #expect(calls.count == 2)
        #expect(calls[1].input.opt?.obscure == true)
    }

    @Test("Mauvais code : le soft error rclone est transmis au prompt suivant")
    func forwardsSoftErrorOnRetry() async throws {
        let rpc = ScriptedRPC(script: [
            questionResponse("config_2fa", state: "*try1"),
            questionResponse("config_2fa", state: "*try2", error: "2FA code rejected"),
            doneResponse
        ])
        let asks = AskRecorder(answers: ["000000", "654321"])

        try await makeFlow(rpc).run(
            name: "icloud", type: "iclouddrive", parameters: [:], obscure: false,
            ask: { option, lastError in await asks.answer(option, lastError) }
        )

        let questions = await asks.questions
        #expect(questions.count == 2)
        #expect(questions[0].lastError == nil)
        #expect(questions[1].lastError == "2FA code rejected")

        let calls = await rpc.calls
        #expect(calls.count == 3)
        #expect(calls[2].input.opt?.state == "*try2")
        #expect(calls[2].input.opt?.result == "654321")
    }

    @Test("Annulation du prompt : ConfigCreateFlowError.cancelled")
    func cancelledQuestionThrows() async throws {
        let rpc = ScriptedRPC(script: [
            questionResponse("config_2fa", state: "*postconfig-2fa")
        ])
        let asks = AskRecorder(answers: [nil])

        await #expect(throws: ConfigCreateFlowError.cancelled) {
            try await makeFlow(rpc).run(
                name: "icloud", type: "iclouddrive", parameters: [:], obscure: false,
                ask: { option, lastError in await asks.answer(option, lastError) }
            )
        }
        // Aucun config/update ne doit partir après une annulation.
        #expect(await rpc.calls.count == 1)
    }

    @Test("Option sans state : ConfigCreateFlowError.malformedContinuation")
    func malformedContinuationThrows() async throws {
        let rpc = ScriptedRPC(script: [
            ConfigCreateResponse(state: "", option: makeOption(name: "config_2fa"), error: nil)
        ])

        await #expect(throws: ConfigCreateFlowError.malformedContinuation) {
            try await makeFlow(rpc).run(
                name: "r", type: "iclouddrive", parameters: [:], obscure: false,
                ask: { _, _ in "unused" }
            )
        }
    }

    @Test("Erreur fatale sans question : ConfigCreateFlowError.rclone")
    func fatalErrorWithoutQuestionThrows() async throws {
        let rpc = ScriptedRPC(script: [
            ConfigCreateResponse(state: "", option: nil, error: "authSRPComplete: sign in failed")
        ])

        // state vide + option nil ⇒ isComplete, mais l'Error doit remonter.
        await #expect(throws: ConfigCreateFlowError.rclone("authSRPComplete: sign in failed")) {
            try await makeFlow(rpc).run(
                name: "r", type: "iclouddrive", parameters: [:], obscure: false,
                ask: { _, _ in "unused" }
            )
        }
    }

    @Test("Tempête de questions : coupe-circuit tooManyQuestions")
    func questionStormThrows() async throws {
        let storm = (0...ConfigCreateFlow.maxQuestions).map { i in
            questionResponse("config_2fa", state: "*loop\(i)")
        }
        let rpc = ScriptedRPC(script: storm)
        let asks = AskRecorder(answers: Array(repeating: "42", count: storm.count))

        await #expect(throws: ConfigCreateFlowError.tooManyQuestions) {
            try await makeFlow(rpc).run(
                name: "r", type: "x", parameters: [:], obscure: false,
                ask: { option, lastError in await asks.answer(option, lastError) }
            )
        }
    }

    @Test("onRemoteWritten déclenché après le create initial, avant la question")
    func remoteWrittenFiresBeforeQuestions() async throws {
        let rpc = ScriptedRPC(script: [
            questionResponse("config_2fa", state: "*st"),
            doneResponse
        ])

        // L'ordre est vérifiable sans horloge : le flag doit être posé au
        // moment où le premier prompt arrive.
        var writtenWhenAsked = false
        var written = false

        try await makeFlow(rpc).run(
            name: "icloud", type: "iclouddrive", parameters: [:], obscure: false,
            onRemoteWritten: { written = true },
            ask: { _, _ in
                writtenWhenAsked = written
                return "123456"
            }
        )

        #expect(written)
        #expect(writtenWhenAsked)
    }
}
