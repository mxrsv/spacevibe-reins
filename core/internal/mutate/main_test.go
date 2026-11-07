package mutate

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// envJournalWriter makes the test binary a journal writer for the two-process test (see two_process_test.go):
// "<home>|<id>|<count>".
const envJournalWriter = "MUTATE_TEST_JOURNAL_WRITER"

// TestMain arms the real-home write guard for the whole package (every test in it writes only under t.TempDir()), and
// turns the binary into a writer process when the two-process test re-executes it.
func TestMain(m *testing.M) {
	fsx.InstallWriteGuard(config.Config{Test: true})
	if spec := os.Getenv(envJournalWriter); spec != "" {
		os.Exit(runJournalWriter(spec))
	}
	os.Exit(m.Run())
}

func runJournalWriter(spec string) int {
	parts := strings.Split(spec, "|")
	if len(parts) != 3 {
		return 2
	}
	count, err := strconv.Atoi(parts[2])
	if err != nil {
		return 2
	}
	r, err := roots.Resolve(homeConfig(parts[0]), "/nonexistent-real-home")
	if err != nil {
		fmt.Fprintln(os.Stderr, "writer", parts[1], "roots:", err)
		return 2
	}
	for i := 0; i < count; i++ {
		if _, err := Record(r, fmt.Sprintf("%s-%d", parts[1], i), nil); err != nil {
			fmt.Fprintln(os.Stderr, "writer", parts[1], "failed:", err)
			return 1
		}
	}
	return 0
}

func homeConfig(root string) config.Config {
	return config.Config{Test: true, UserHome: root, ClaudeConfigDir: root + "/.claude", CodexHome: root + "/.codex", Home: root + "/.spacevibe"}
}
