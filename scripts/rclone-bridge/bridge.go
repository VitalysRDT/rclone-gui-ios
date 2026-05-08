// Package rclonebridge wraps github.com/rclone/rclone/librclone/librclone
// so that gomobile can bind it. gomobile only supports functions returning
// 0, 1, or (T, error); librclone.RPC returns (string, int) which is not
// compatible. This bridge wraps the result in an exported struct.
package rclonebridge

import (
	"encoding/json"
	"os"

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

// SetEnv updates a process environment variable. Must be used instead of
// the host's setenv(3) when the host is Swift on iOS: gomobile boots the
// Go runtime at framework load time and caches environ in an internal
// table that is not refreshed by host-side setenv. Calling os.Setenv from
// Go updates both the internal table and the C-level environ, so the
// rclone runtime sees the new value.
//
// Typical use: call SetEnv("RCLONE_CONFIG", "/path/to/rclone.conf") before
// Initialize() so configfile.Install() picks up the right path.
func SetEnv(name, value string) {
	_ = os.Setenv(name, value)
}

// GetEnv returns a process environment variable from Go's perspective.
// Useful for diagnostics — confirms whether SetEnv (or host setenv)
// reached the Go runtime.
func GetEnv(name string) string {
	return os.Getenv(name)
}

// Diagnostic returns a small JSON document describing the runtime
// environment as seen from Go. Used by the host to confirm that the
// config path is wired correctly. Never panics; missing fields are
// returned as empty strings.
func Diagnostic() string {
	cwd, _ := os.Getwd()
	payload := map[string]string{
		"cwd":           cwd,
		"home":          os.Getenv("HOME"),
		"rclone_config": os.Getenv("RCLONE_CONFIG"),
		"tmpdir":        os.Getenv("TMPDIR"),
	}
	out, err := json.Marshal(payload)
	if err != nil {
		return `{"error":"json marshal failed"}`
	}
	return string(out)
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
