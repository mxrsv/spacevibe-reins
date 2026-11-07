package statusline

import (
	"os"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
)

// TestMain arms the real-home write guard for the package: every test writes only under t.TempDir().
func TestMain(m *testing.M) {
	fsx.InstallWriteGuard(config.Config{Test: true})
	os.Exit(m.Run())
}
