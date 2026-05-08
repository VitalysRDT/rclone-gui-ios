// Package rclonebridge wraps github.com/rclone/rclone/librclone/librclone
// so that gomobile can bind it. gomobile only supports functions returning
// 0, 1, or (T, error); librclone.RPC returns (string, int) which is not
// compatible. This bridge wraps the result in an exported struct.
package rclonebridge

import (
	"github.com/rclone/rclone/librclone/librclone"

	// Blank import: gomobile/gobind resolves the bind package via the
	// module graph, so the bridge module must declare the dependency.
	_ "golang.org/x/mobile/bind"
)

// RPCResult is the result of an RPC call. Both fields are exported
// so gomobile generates Swift accessors.
type RPCResult struct {
	Output string
	Status int
}

// Initialize starts the rclone runtime. Idempotent — safe to call multiple
// times. Must be called before any RPC.
func Initialize() {
	librclone.Initialize()
}

// Finalize tears down the rclone runtime. Optional — only useful when the
// host process intends to remove all rclone state.
func Finalize() {
	librclone.Finalize()
}

// RPC sends a raw rclone rc method call. inputJSON should be a JSON object
// (use "{}" for no parameters). Status follows HTTP-style codes:
// 200..<300 = success, anything else = error.
func RPC(method, inputJSON string) *RPCResult {
	out, status := librclone.RPC(method, inputJSON)
	return &RPCResult{Output: out, Status: status}
}
