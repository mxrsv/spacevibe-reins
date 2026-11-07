package usage

import (
	"encoding/binary"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/roots"
)

// tempHome is a throwaway HOME. Its path has its symlinks resolved (macOS /var is a link). Tests never touch
// the real home: the roots come from here and SPACEVIBE_TEST=1 turns the guard on.
type tempHome struct {
	root string
	t    *testing.T
}

func newTempHome(t *testing.T) tempHome {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return tempHome{root, t}
}

func (h tempHome) path(rel string) string { return filepath.Join(h.root, rel) }
func (h tempHome) data() string           { return h.path(".spacevibe") }

func (h tempHome) cfg() config.Config {
	return config.Config{Test: true, UserHome: h.root, ClaudeConfigDir: h.path(".claude"), CodexHome: h.path(".codex"), Home: h.data()}
}

func (h tempHome) roots() roots.Roots {
	h.t.Helper()
	r, err := roots.Resolve(h.cfg(), h.t.TempDir())
	if err != nil {
		h.t.Fatal(err)
	}
	return r
}

func (h tempHome) write(rel string, content any) string {
	h.t.Helper()
	p := h.path(rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		h.t.Fatal(err)
	}
	var data []byte
	switch c := content.(type) {
	case string:
		data = []byte(c)
	case []byte:
		data = c
	}
	if err := os.WriteFile(p, data, 0o644); err != nil {
		h.t.Fatal(err)
	}
	return p
}

// attach is a hook attachment record in the shape Claude Code writes it; nothing is copied from real logs.
func attach(day string, attachment map[string]any) string {
	record := map[string]any{"type": "attachment", "timestamp": day + "T10:00:00Z", "attachment": attachment}
	data, _ := json.Marshal(record)
	return string(data)
}

func codexCall(day, skill string) string {
	return `{"timestamp":"` + day + `T10:00:00Z","type":"response_item","payload":{"type":"function_call","arguments":"cat skills/` + skill + `/SKILL.md"}}` + "\n"
}

// zstdRawFrame is a zstd frame made of one raw (uncompressed) block: valid zstd, no compressor needed.
// Single segment, 4-byte content size.
func zstdRawFrame(payload []byte) []byte {
	out := []byte{0x28, 0xB5, 0x2F, 0xFD, 0xA0}
	out = binary.LittleEndian.AppendUint32(out, uint32(len(payload)))
	header := uint32(len(payload))<<3 | 1 // last block, type raw
	out = append(out, byte(header), byte(header>>8), byte(header>>16))
	return append(out, payload...)
}

func scan(t *testing.T, h tempHome) Result {
	t.Helper()
	return mustScan(t, NewScanner(h.roots()))
}

func mustScan(t *testing.T, s *Scanner) Result {
	t.Helper()
	res, err := s.Scan(t.Context(), nil)
	if err != nil {
		t.Fatalf("scan: %v", err)
	}
	return res
}

func ptr[T any](v T) *T { return &v }

func lines(items ...string) string { return strings.Join(items, "\n") }
