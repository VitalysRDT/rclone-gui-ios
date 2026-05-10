//
//  RemoteConnectionTester.swift
//  Rclone GUI — Services
//
//  Tests a remote by listing its root via `operations/list`. Used by
//  the wizard's recap step to validate config + credentials before the
//  user commits.
//
//  Why `operations/list` and not `operations/about`?
//  - `about` is faster but not all backends implement it; failures
//    there give false negatives.
//  - `list` works on every backend that the user is realistically
//    going to want to add. Empty bucket / empty drive is fine — we
//    just confirm the call returns 200.
//

import Foundation

enum RemoteConnectionTester {

    enum TestError: LocalizedError, Equatable {
        case timeout(seconds: Int)
        case rcloneError(String)

        var errorDescription: String? {
            switch self {
            case .timeout(let seconds):
                return "Délai dépassé (\(seconds)s)"
            case .rcloneError(let message):
                return message
            }
        }
    }

    struct Result: Sendable, Equatable {
        let itemCount: Int
        let sample: [String]
    }

    /// Tests the given remote by listing its root. Throws on timeout or
    /// rclone error. Always returns within `timeoutSeconds` even if
    /// rclone hangs.
    static func test(
        remote: String,
        timeoutSeconds: Int = 10,
        sampleLimit: Int = 5
    ) async throws -> Result {
        let task = Task<Result, Error> {
            struct ListInput: Encodable {
                let fs: String
                let remote: String
                let opt: ListOpt
            }
            struct ListOpt: Encodable {
                let dirsOnly: Bool
                let recurse: Bool
                let noModTime: Bool
            }
            struct ListItem: Decodable {
                let Name: String
            }
            struct ListResponse: Decodable {
                let list: [ListItem]
            }

            let input = ListInput(
                fs: remote.hasSuffix(":") ? remote : "\(remote):",
                remote: "",
                opt: ListOpt(dirsOnly: false, recurse: false, noModTime: true)
            )
            let response: ListResponse
            do {
                response = try await RcloneCore.shared.rpc("operations/list", input: input)
            } catch {
                throw TestError.rcloneError(error.localizedDescription)
            }

            let names = response.list.map(\.Name)
            return Result(
                itemCount: names.count,
                sample: Array(names.prefix(sampleLimit))
            )
        }

        let timeoutTask = Task<Void, Error> {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            task.cancel()
            throw TestError.timeout(seconds: timeoutSeconds)
        }

        do {
            let result = try await task.value
            timeoutTask.cancel()
            return result
        } catch is CancellationError {
            throw TestError.timeout(seconds: timeoutSeconds)
        } catch {
            timeoutTask.cancel()
            if error is TestError { throw error }
            throw TestError.rcloneError(error.localizedDescription)
        }
    }
}
