package rclonebridge

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/rclone/rclone/fs/config"
)

const plaintextConf = "[s3remote]\ntype = s3\nprovider = AWS\n"

// writeEncryptedConf produces an RCLONE_ENCRYPT_V0 file the same way
// `rclone config encryption set` does.
func writeEncryptedConf(t *testing.T, password string) string {
	t.Helper()
	if err := config.SetConfigPassword(password); err != nil {
		t.Fatalf("SetConfigPassword: %v", err)
	}
	defer config.ClearConfigPassword()

	var buf bytes.Buffer
	if err := config.Encrypt(strings.NewReader(plaintextConf), &buf); err != nil {
		t.Fatalf("Encrypt: %v", err)
	}
	path := filepath.Join(t.TempDir(), "rclone.conf")
	if err := os.WriteFile(path, buf.Bytes(), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	return path
}

func TestDecryptConfigRoundTrip(t *testing.T) {
	path := writeEncryptedConf(t, "correct horse")

	res := DecryptConfig(path, "correct horse")
	if res.Status != 200 {
		t.Fatalf("expected 200, got %d: %s", res.Status, res.Output)
	}
	if res.Output != plaintextConf {
		t.Fatalf("plaintext mismatch:\n%q\nvs\n%q", res.Output, plaintextConf)
	}
}

func TestDecryptConfigWrongPassword(t *testing.T) {
	path := writeEncryptedConf(t, "correct horse")

	// Must return an error status — and crucially must NOT os.Exit.
	res := DecryptConfig(path, "wrong password")
	if res.Status == 200 {
		t.Fatalf("expected failure status, got 200: %s", res.Output)
	}
}

func TestDecryptConfigEmptyPassword(t *testing.T) {
	path := writeEncryptedConf(t, "correct horse")

	res := DecryptConfig(path, "")
	if res.Status == 200 {
		t.Fatalf("expected failure status for empty password, got 200")
	}
}

func TestDecryptConfigPlaintextPassthrough(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rclone.conf")
	if err := os.WriteFile(path, []byte(plaintextConf), 0o600); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	res := DecryptConfig(path, "anything")
	if res.Status != 200 || res.Output != plaintextConf {
		t.Fatalf("expected passthrough, got %d: %q", res.Status, res.Output)
	}
}
