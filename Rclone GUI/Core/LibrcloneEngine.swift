//
//  LibrcloneEngine.swift
//  Rclone GUI — Core
//
//  Real engine that bridges to librclone via the gomobile-generated
//  RcloneKit.xcframework. Compiled only when `RcloneKit` can be imported,
//  so the rest of the project keeps building before the xcframework is
//  produced.
//
//  After running `scripts/build-rclone.sh` for the first time, inspect
//      Frameworks/RcloneKit.xcframework/ios-arm64/RcloneKit.framework/Headers/Librclone.objc.h
//  and adjust the symbol names below if gomobile generated different ones.
//

#if canImport(RcloneKit)
import Foundation
import RcloneKit

public struct LibrcloneEngine: RcloneEngine {
    public init() {}

    public func initialize() async throws {
        // Go API:
        //     func RcloneInitialize()
        // Likely gomobile-generated Swift symbol:
        //     LibrcloneRcloneInitialize()
        //
        // If the symbol differs, replace this single line with the actual one
        // exported by your build of RcloneKit.xcframework.
        LibrcloneRcloneInitialize()
    }

    public func rpcRaw(method: String, inputJSON: String) async throws -> String {
        // Go API:
        //     func RcloneRPC(method, input string) (output string, status int)
        // Most common gomobile output for two return values is the
        // inout-pointer pattern below. If the build instead exposes a
        // tuple-returning function, replace the call site accordingly.
        var output: NSString?
        var status: Int = 0
        LibrcloneRcloneRPC(method, inputJSON, &output, &status)

        let outputStr = (output as String?) ?? ""

        if (200..<300).contains(status) {
            return outputStr
        } else {
            throw RcloneError.rcloneError(code: status, method: method, message: outputStr)
        }
    }
}
#endif
