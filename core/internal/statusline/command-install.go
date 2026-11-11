package statusline

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// genericFailure is what the command prints for an error that carries no safe message (S-R3).
const genericFailure = "The operation failed; no input or error payload is logged."

// environment is the config and roots of this process, with the real-home guard armed under SPACEVIBE_TEST=1.
func environment() (config.Config, roots.Roots, error) {
	cfg, err := config.Load()
	if err != nil {
		return config.Config{}, roots.Roots{}, err
	}
	return resolve(cfg)
}

func resolve(cfg config.Config) (config.Config, roots.Roots, error) {
	home, err := roots.RealHome()
	if err != nil {
		return config.Config{}, roots.Roots{}, err
	}
	r, err := roots.Resolve(cfg, home)
	if err != nil {
		return config.Config{}, roots.Roots{}, err
	}
	fsx.InstallWriteGuard(cfg)
	return cfg, r, nil
}

// failed prints the safe sentence of err, or the generic one, and returns exit status 1.
func failed(stderr io.Writer, err error) int {
	if e, ok := coreerr.As(err); ok {
		report(stderr, e.Message)
	} else {
		report(stderr, genericFailure)
	}
	return 1
}

// executablePath is the running executable with its links resolved. os.Executable, never argv[0]: argv[0] is
// whatever the caller typed (a relative name, a PATH lookup) and can name another file (G-fix.19).
func executablePath() (string, error) {
	path, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(path)
}

func runInstall(stdout, stderr io.Writer) int {
	cfg, r, err := environment()
	if err != nil {
		report(stderr, err.Error()) // config and roots errors name a variable or a root, never content
		return 1
	}
	binary, err := executablePath()
	if err != nil {
		report(stderr, "The running executable could not be found.")
		return 1
	}
	entry, err := Install(cfg, r, binary)
	if err != nil {
		return failed(stderr, err)
	}
	if entry == nil {
		fmt.Fprintln(stdout, "Claude limit capture is already enabled.")
		return 0
	}
	fmt.Fprintln(stdout, "Claude limit capture enabled. Undo settings with:")
	fmt.Fprintf(stdout, "%s statusline %s %s\n", Quote(Executable(r)), cmdUndo, Quote(entry.ID))
	return 0
}

func runUndo(id string, stdout, stderr io.Writer) int {
	_, r, err := environment()
	if err != nil {
		report(stderr, err.Error())
		return 1
	}
	if err := Undo(r, id); err != nil {
		return failed(stderr, err)
	}
	fmt.Fprintln(stdout, "Settings restored. The inactive collector binary was kept.")
	return 0
}

func runUninstall(stdout, stderr io.Writer) int {
	_, r, err := environment()
	if err != nil {
		report(stderr, err.Error())
		return 1
	}
	entry, err := Uninstall(r)
	if err != nil {
		return failed(stderr, err)
	}
	if entry == nil {
		fmt.Fprintln(stdout, "Claude limit capture is not enabled; nothing was changed.")
		return 0
	}
	fmt.Fprintln(stdout, "Claude limit capture removed. The inactive collector binary was kept.")
	return 0
}
