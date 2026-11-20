package usage

import (
	"errors"
	"slices"
	"testing"

	"spacevibe.dev/core/internal/clis"
)

func TestParsersMatchRegistry(t *testing.T) {
	if err := parsers.Check(); err != nil {
		t.Fatal(err)
	}
}

// Every CLI with the usage concept has exactly one element in each wire array, in registry order, even with no logs.
func TestEveryUsageCLIIsInEachArray(t *testing.T) {
	r, err := aggregate(map[string]cachedFile{}, 0)
	if err != nil {
		t.Fatal(err)
	}
	want := clis.IDsWith(clis.Usage)
	ids := func(n int, at func(int) clis.ID) []clis.ID {
		out := make([]clis.ID, n)
		for i := range out {
			out[i] = at(i)
		}
		return out
	}
	for name, got := range map[string][]clis.ID{
		"totals":   ids(len(r.Totals), func(i int) clis.ID { return r.Totals[i].CLI }),
		"windows":  ids(len(r.Windows), func(i int) clis.ID { return r.Windows[i].CLI }),
		"sessions": ids(len(r.Sessions), func(i int) clis.ID { return r.Sessions[i].CLI }),
	} {
		if !slices.Equal(got, want) {
			t.Errorf("%s lists %v, want %v", name, got, want)
		}
	}
	if totalsOf(r, Claude).Skill == nil {
		t.Error("the maps of an empty CLI must be empty, not null")
	}
}

// For never answers with another CLI's element: an unknown id wraps clis.ErrUnknownCLI, a CLI whose logs are not
// scanned wraps clis.ErrConceptAbsent.
func TestForOfAnotherCLIIsAnError(t *testing.T) {
	totals := Totals{{CLI: Codex, Skill: map[string]NameUsage{"codex-only": {Sessions: 1}}}}
	for _, c := range []struct {
		id   clis.ID
		want error
	}{{clis.Gemini, clis.ErrConceptAbsent}, {"nope", clis.ErrUnknownCLI}} {
		if got, err := totals.For(c.id); !errors.Is(err, c.want) || got.Skill != nil {
			t.Errorf("Totals.For(%s) = %+v, %v", c.id, got, err)
		}
		if _, err := (Windows{}).For(c.id); !errors.Is(err, c.want) {
			t.Errorf("Windows.For(%s) = %v", c.id, err)
		}
	}
	if _, err := totals.For(Claude); err == nil {
		t.Error("Totals.For(claude) answered for a result without Claude Code")
	}
}
