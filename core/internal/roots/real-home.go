package roots

import (
	"errors"
	"os"
	"os/user"
	"strconv"
)

// RealHome is the account's home folder from the password database, not from $HOME, so a test
// that overrides HOME cannot hide it (H1). It fails closed: it never falls back to $HOME.
//
// Why user.LookupId and not user.Current or os.UserHomeDir: on Linux without cgo user.Current falls
// back to $HOME when /etc/passwd has no entry, and os.UserHomeDir is $HOME. user.LookupId has no
// such fallback. On darwin with CGO_ENABLED=0 the standard library calls getpwuid_r through libc
// (os/user/cgo_lookup_syscall.go), so no cgo is needed. The "osusergo" build tag would swap that for
// a $HOME-reading stub on darwin, so no-osusergo.go refuses to build with it.
// Limit: on Linux without cgo, an account missing from /etc/passwd (a container with an arbitrary
// uid) makes the standard library fall back to $HOME; SpaceVibe's test hosts are macOS.
// Windows has no uid (os.Getuid is -1); user.Current reads the account token there, not $HOME.
func RealHome() (string, error) {
	var u *user.User
	var err error
	if uid := os.Getuid(); uid >= 0 {
		u, err = user.LookupId(strconv.Itoa(uid))
	} else {
		u, err = user.Current()
	}
	if err != nil {
		return "", errors.New("cannot read the account's home folder from the password database")
	}
	if u.HomeDir == "" {
		return "", errors.New("the password database has no home folder for this account")
	}
	return u.HomeDir, nil
}
