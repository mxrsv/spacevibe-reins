package goldentest

import (
	"errors"
	"os"
	"path/filepath"
)

// updateEnv, set to 1, makes the golden tests that support it write their result to the golden file instead of
// comparing (RewriteGolden). It is for a deliberate change of shape or fixture only (spec MC18, MC26): run it once,
// then check every value that changed, update SHA256SUMS and commit the new bytes on purpose. The freeze check
// (TestFreezeSHA256SUMS) still fails until SHA256SUMS is updated, so a rewrite cannot slip in unnoticed.
const updateEnv = "GOLDENTEST_UPDATE"

// Updating reports whether this run rewrites goldens.
func Updating() bool { return os.Getenv(updateEnv) == "1" }

// RewriteGolden writes tree as golden/<name>.json in the canonical form every golden comparison reads. The tree must
// already be the projection the golden holds ($HOME tokens, sorted where the test sorts).
func RewriteGolden(name string, tree any) error {
	dir, err := FixturesDir()
	if err != nil {
		return err
	}
	data, err := Canonical(tree)
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(dir, "golden", name+".json"), data, 0o644); err != nil {
		return errors.New("goldentest: cannot write the golden file")
	}
	return nil
}
