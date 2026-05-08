// Package host is a minimal iOS-safe stub of github.com/shirou/gopsutil/v3/host.
// It exposes only the functions rclone consumes (PlatformInformation,
// KernelVersion, KernelArch) and avoids the transitive dep on
// gopsutil/process → gopsutil/cpu, whose darwin cgo files include
// <libproc.h> which is unavailable in the iOS SDK and breaks the
// gomobile build.
package host

import (
	"runtime"
	"strings"
)

// PlatformInformation returns the OS platform/family/version. On iOS we
// return "ios" / "darwin" / "" since runtime.GOOS reports darwin for both
// macOS and iOS but the Apple iOS SDK doesn't expose userspace utmp.
func PlatformInformation() (platform, family, version string, err error) {
	if runtime.GOOS == "darwin" {
		return "ios", "darwin", "", nil
	}
	return strings.ToLower(runtime.GOOS), runtime.GOOS, "", nil
}

// KernelVersion is unavailable in the iOS sandbox; return empty string.
func KernelVersion() (string, error) {
	return "", nil
}

// KernelArch returns the runtime architecture (e.g. "arm64").
func KernelArch() (string, error) {
	return runtime.GOARCH, nil
}
