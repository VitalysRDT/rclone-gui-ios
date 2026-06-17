// Package rclonebridge wraps github.com/rclone/rclone/librclone/librclone
// so that gomobile can bind it. gomobile only supports functions returning
// 0, 1, or (T, error); librclone.RPC returns (string, int) which is not
// compatible. This bridge wraps the result in an exported struct.
package rclonebridge

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/rclone/rclone/fs"
	"github.com/rclone/rclone/fs/config"
	"github.com/rclone/rclone/fs/operations"
	"github.com/rclone/rclone/librclone/librclone"

	// Blank imports: each subsystem registers its rc.Calls in its own
	// init(). Without these the bridge would only expose the calls
	// declared by the librclone package itself (config/*, core/*) and
	// any attempt at operations/list, sync/copy, etc. would 404 with
	// "couldn't find method". The upstream librclone/librclone.go
	// binary does the same thing — we mirror it here, minus FUSE
	// (cmd/{cmount,mount,mount2}) which won't link on iOS.
	_ "github.com/rclone/rclone/backend/all"   // all backends (drive, s3, ...)
	_ "github.com/rclone/rclone/fs/operations" // operations/* rc commands
	_ "github.com/rclone/rclone/fs/sync"       // sync/* rc commands

	// gomobile/gobind resolves the bind package via the module graph.
	_ "golang.org/x/mobile/bind"
)

// RPCResult is the result of an RPC call. Both fields are exported
// so gomobile generates Swift accessors.
type RPCResult struct {
	Output string
	Status int
}

var streamSessions sync.Map // map[string]*http.Server

// ─── Live log capture (Phase E2) ──────────────────────────────────────────
// rclone logs through log/slog. We tee its default handler into a bounded
// ring buffer that the host polls via DrainLogs, so Settings → Logs can show
// the engine's real activity (notices, warnings, errors) — no backend server,
// nothing leaves the device.

var (
	logMu     sync.Mutex
	logRing   []string
	logActive bool
)

const logRingCap = 2000

type captureHandler struct{ inner slog.Handler }

func (h *captureHandler) Enabled(ctx context.Context, l slog.Level) bool {
	return h.inner.Enabled(ctx, l)
}

func (h *captureHandler) Handle(ctx context.Context, r slog.Record) error {
	line := r.Time.UTC().Format(time.RFC3339) + "\t" + slogLevelLabel(r.Level) + "\t" + r.Message
	logMu.Lock()
	logRing = append(logRing, line)
	if len(logRing) > logRingCap {
		logRing = logRing[len(logRing)-logRingCap:]
	}
	logMu.Unlock()
	return h.inner.Handle(ctx, r)
}

func (h *captureHandler) WithAttrs(a []slog.Attr) slog.Handler {
	return &captureHandler{inner: h.inner.WithAttrs(a)}
}

func (h *captureHandler) WithGroup(name string) slog.Handler {
	return &captureHandler{inner: h.inner.WithGroup(name)}
}

func slogLevelLabel(l slog.Level) string {
	switch {
	case l < slog.LevelInfo:
		return "DEBUG"
	case l < slog.Level(2): // rclone NOTICE = 2
		return "INFO"
	case l < slog.LevelWarn:
		return "NOTICE"
	case l < slog.LevelError:
		return "WARNING"
	default:
		return "ERROR"
	}
}

// StartLogCapture begins teeing rclone's slog output into the ring buffer.
// Idempotent — call once at startup. Preserves the existing handler (stderr).
func StartLogCapture() {
	logMu.Lock()
	defer logMu.Unlock()
	if logActive {
		return
	}
	slog.SetDefault(slog.New(&captureHandler{inner: slog.Default().Handler()}))
	logActive = true
}

// DrainLogs returns the log lines captured since the last call as a JSON array
// of "RFC3339\tLEVEL\tmessage" strings, then clears the buffer. Returns "[]"
// when empty.
func DrainLogs() string {
	logMu.Lock()
	defer logMu.Unlock()
	if len(logRing) == 0 {
		return "[]"
	}
	out, err := json.Marshal(logRing)
	logRing = logRing[:0]
	if err != nil {
		return "[]"
	}
	return string(out)
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

// DecryptConfig decrypts an rclone-encrypted configuration file
// (RCLONE_ENCRYPT_V0 format, produced by `rclone config encryption set`)
// and returns the plaintext INI as Output with Status 200.
//
// It exists because handing an encrypted rclone.conf to librclone is
// fatal on iOS: the lazy config load path ends in fs.Fatalf →
// os.Exit when no terminal is available to prompt for the password
// (fs/config/config.go + config_read_password.go). This function uses
// config.Decrypt directly with AskPassword disabled so a wrong password
// is a recoverable error (Status 400), never a process kill.
//
// The global configKey is cleared before returning so later config
// saves performed by librclone stay plaintext.
func DecryptConfig(path string, password string) *RPCResult {
	ci := fs.GetConfig(context.Background())
	oldAsk := ci.AskPassword
	ci.AskPassword = false
	defer func() { ci.AskPassword = oldAsk }()
	defer config.ClearConfigPassword()

	if err := config.SetConfigPassword(password); err != nil {
		return &RPCResult{Output: jsonError(err), Status: 400}
	}

	f, err := os.Open(path)
	if err != nil {
		return &RPCResult{Output: jsonError(err), Status: 400}
	}
	defer func() { _ = f.Close() }()

	r, err := config.Decrypt(f)
	if err != nil {
		return &RPCResult{Output: jsonError(err), Status: 400}
	}
	out, err := io.ReadAll(r)
	if err != nil {
		return &RPCResult{Output: jsonError(err), Status: 400}
	}
	return &RPCResult{Output: string(out), Status: 200}
}

// StartFileHTTP starts a loopback-only HTTP server that serves one rclone
// object with byte-range support. The returned URL contains an unguessable
// token and is safe to pass to AVPlayer. Call StopFileHTTP with the returned
// session id when playback ends.
//
// Return format:
//   {"id":"...","url":"http://127.0.0.1:12345/file?token=..."}
func StartFileHTTP(remote, remotePath string) string {
	id := randomHex(16)
	token := randomHex(24)

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return jsonError(err)
	}

	mux := http.NewServeMux()
	// Server-level timeouts protect against orphaned sessions if AVPlayer
	// crashes mid-playback. ReadHeaderTimeout caps slow-headers, IdleTimeout
	// reclaims sockets sitting idle between range reads. No WriteTimeout: a
	// long movie may legitimately take hours to stream.
	server := &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       2 * time.Minute,
	}
	mux.HandleFunc("/file", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("token") != token {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		if r.Method != http.MethodGet && r.Method != http.MethodHead {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Use the request context so client disconnects cancel rclone reads
		// instead of leaving them hanging until the next GC pass.
		ctx := r.Context()
		f, obj, err := openObject(ctx, remote, remotePath)
		if err != nil {
			http.Error(w, err.Error(), http.StatusNotFound)
			return
		}
		_ = f

		size := obj.Size()
		contentType := mime.TypeByExtension(filepath.Ext(remotePath))
		if contentType == "" {
			contentType = "application/octet-stream"
		}
		w.Header().Set("Accept-Ranges", "bytes")
		w.Header().Set("Content-Type", contentType)
		if size >= 0 {
			w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
		}

		if r.Method == http.MethodHead {
			w.WriteHeader(http.StatusOK)
			return
		}

		var options []fs.OpenOption
		var copyLimit int64 = -1
		rangeHeader := r.Header.Get("Range")
		if rangeHeader != "" && size >= 0 {
			rangeOption, err := fs.ParseRangeOption(rangeHeader)
			if err != nil {
				http.Error(w, "bad range", http.StatusRequestedRangeNotSatisfiable)
				return
			}
			start, limit := rangeOption.Decode(size)
			end := size - 1
			if limit >= 0 {
				end = start + limit - 1
				copyLimit = limit
			}
			options = append(options, rangeOption)
			w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, size))
			w.Header().Set("Content-Length", strconv.FormatInt(end-start+1, 10))
			w.WriteHeader(http.StatusPartialContent)
		}

		rc, err := operations.Open(ctx, obj, options...)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rc.Close()

		if copyLimit >= 0 {
			_, _ = io.CopyN(w, rc, copyLimit)
			return
		}
		_, _ = io.Copy(w, rc)
	})

	streamSessions.Store(id, server)
	go func() {
		_ = server.Serve(listener)
		streamSessions.Delete(id)
	}()

	payload := map[string]string{
		"id":  id,
		"url": "http://" + listener.Addr().String() + "/file?token=" + token,
	}
	out, err := json.Marshal(payload)
	if err != nil {
		return jsonError(err)
	}
	return string(out)
}

// StopFileHTTP shuts down a streaming server created by StartFileHTTP.
func StopFileHTTP(id string) {
	if value, ok := streamSessions.Load(id); ok {
		if server, ok := value.(*http.Server); ok {
			_ = server.Shutdown(context.Background())
		}
		streamSessions.Delete(id)
	}
}

func openObject(ctx context.Context, remote, remotePath string) (fs.Fs, fs.Object, error) {
	fsName := remote
	if !strings.HasSuffix(fsName, ":") {
		fsName += ":"
	}
	f, err := fs.NewFs(ctx, fsName)
	if err != nil {
		return nil, nil, err
	}
	obj, err := f.NewObject(ctx, remotePath)
	if err != nil {
		return nil, nil, err
	}
	return f, obj, nil
}

func randomHex(bytes int) string {
	buf := make([]byte, bytes)
	if _, err := rand.Read(buf); err != nil {
		return "fallback"
	}
	return hex.EncodeToString(buf)
}

func jsonError(err error) string {
	out, marshalErr := json.Marshal(map[string]string{"error": err.Error()})
	if marshalErr != nil {
		return `{"error":"unknown"}`
	}
	return string(out)
}
