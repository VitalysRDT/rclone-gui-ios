// Package m1cpu is a no-op stub used only when building rclone for iOS via
// gomobile. The upstream package github.com/shoenig/go-m1cpu calls IOKit
// APIs (kIOMasterPortDefault) that are unavailable on iOS, breaking the
// build. Replacing it with this stub avoids that dependency entirely. We
// always report "not Apple Silicon" so callers fall back to portable code
// paths.
package m1cpu

func IsAppleSilicon() bool      { return false }
func PCoreHz() uint64           { return 0 }
func ECoreHz() uint64           { return 0 }
func PCoreGHz() float64         { return 0 }
func ECoreGHz() float64         { return 0 }
func PCoreCount() int           { return 0 }
func ECoreCount() int           { return 0 }
func PCoreCache() (int, int, int) { return 0, 0, 0 }
func ECoreCache() (int, int, int) { return 0, 0, 0 }
func ModelName() string         { return "" }
