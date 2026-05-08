module rclonebridge

go 1.25.0

require (
	github.com/rclone/rclone v1.68.0
	golang.org/x/mobile v0.0.0-20240716161057-1ad2df20a8b6
)

require (
	github.com/abbot/go-http-auth v0.4.0 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.2.0 // indirect
	github.com/coreos/go-semver v0.3.1 // indirect
	github.com/coreos/go-systemd/v22 v22.5.0 // indirect
	github.com/go-chi/chi/v5 v5.1.0 // indirect
	github.com/google/uuid v1.6.0 // indirect
	github.com/jzelinskie/whirlpool v0.0.0-20201016144138-0675e54bb004 // indirect
	github.com/mattn/go-colorable v0.1.13 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/mitchellh/go-homedir v1.1.0 // indirect
	github.com/prometheus/client_golang v1.19.1 // indirect
	github.com/prometheus/client_model v0.5.0 // indirect
	github.com/prometheus/common v0.48.0 // indirect
	github.com/prometheus/procfs v0.12.0 // indirect
	github.com/shirou/gopsutil/v3 v3.24.5 // indirect
	github.com/sirupsen/logrus v1.9.3 // indirect
	github.com/smartystreets/goconvey v1.8.1 // indirect
	github.com/spf13/pflag v1.0.5 // indirect
	github.com/unknwon/goconfig v1.0.0 // indirect
	golang.org/x/crypto v0.50.0 // indirect
	golang.org/x/mod v0.34.0 // indirect
	golang.org/x/net v0.53.0 // indirect
	golang.org/x/sync v0.20.0 // indirect
	golang.org/x/sys v0.43.0 // indirect
	golang.org/x/term v0.42.0 // indirect
	golang.org/x/text v0.36.0 // indirect
	golang.org/x/time v0.5.0 // indirect
	golang.org/x/tools v0.43.0 // indirect
	google.golang.org/protobuf v1.34.2 // indirect
)

replace github.com/rclone/rclone => ../../.build/rclone/rclone

// iOS-safe stub: upstream go-m1cpu uses IOKit APIs unavailable on iOS,
// breaking the gomobile cross-build. The stub reports "not Apple Silicon"
// so callers fall through to portable code paths.
replace github.com/shoenig/go-m1cpu => ./stubs/go-m1cpu

// iOS-safe stub: upstream gopsutil/v3/host transitively imports
// gopsutil/v3/process and gopsutil/v3/cpu whose darwin cgo files include
// <libproc.h>, unavailable in the iOS SDK. The stub provides only the
// three functions rclone's lib/buildinfo consumes.
replace github.com/shirou/gopsutil/v3 => ./stubs/gopsutil-v3
