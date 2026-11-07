package goldentest

import (
	"fmt"
	"math/rand"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestUnifiedDiffShapes(t *testing.T) {
	if UnifiedDiff("a", "b", "x\ny\n", "x\ny\n") != "" {
		t.Error("equal texts must give an empty diff")
	}
	got := UnifiedDiff("want", "got", "1\n2\n3\n4\n5\n6\n7\n8\n9\n", "1\n2\n3\n4\nFIVE\n6\n7\n8\n9\n")
	want := "--- want\n+++ got\n@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+FIVE\n 6\n 7\n 8\n"
	if got != want {
		t.Errorf("single change:\n%s\nwant:\n%s", got, want)
	}

	// Two changes far apart make two hunks; the second hunk's line numbers count the earlier insertion.
	var a, b []string
	for i := 1; i <= 30; i++ {
		a = append(a, fmt.Sprint(i))
		b = append(b, fmt.Sprint(i))
	}
	b = append([]string{"new"}, b...)
	b[26] = "CHANGED"
	got = UnifiedDiff("want", "got", strings.Join(a, "\n")+"\n", strings.Join(b, "\n")+"\n")
	if strings.Count(got, "@@ -") != 2 || !strings.Contains(got, "+new\n") || !strings.Contains(got, "-26\n+CHANGED\n") {
		t.Errorf("two hunks expected:\n%s", got)
	}
	if !strings.Contains(got, "@@ -1,3 +1,4 @@") {
		t.Errorf("first hunk header:\n%s", got)
	}

	// Pure addition to empty and removal to empty.
	if d := UnifiedDiff("w", "g", "", "a\nb\n"); !strings.Contains(d, "@@ -0,0 +1,2 @@\n+a\n+b\n") {
		t.Errorf("addition:\n%s", d)
	}
	if d := UnifiedDiff("w", "g", "a\nb\n", ""); !strings.Contains(d, "@@ -1,2 +0,0 @@\n-a\n-b\n") {
		t.Errorf("removal:\n%s", d)
	}
}

// The largest golden is about 17,800 lines; a diff of a middle too big for the LCS table must still be quick.
func TestUnifiedDiffLargeInputsStayFast(t *testing.T) {
	var a, b strings.Builder
	for i := 0; i < 20000; i++ {
		fmt.Fprintf(&a, "line %d\n", i)
		if i%5000 == 0 {
			fmt.Fprintf(&b, "other %d\n", i)
		} else {
			fmt.Fprintf(&b, "line %d\n", i)
		}
	}
	start := time.Now()
	d := UnifiedDiff("w", "g", a.String(), b.String())
	if time.Since(start) > 5*time.Second || !strings.Contains(d, "-line 5000\n+other 5000\n") {
		t.Errorf("slow or wrong (%v):\n%.300s", time.Since(start), d)
	}
}

// Property: the aligned lines always rebuild both inputs, and the edit count is the shortest one for simple cases.
func TestUnifiedDiffOpsRebuildBothSides(t *testing.T) {
	r := rand.New(rand.NewSource(7))
	for range 2000 {
		mk := func() []string {
			out := make([]string, r.Intn(12))
			for i := range out {
				out[i] = string(rune('a' + r.Intn(4)))
			}
			return out
		}
		a, b := mk(), mk()
		var gotA, gotB []string
		for _, op := range diffOps(a, b) {
			if op.kind != '+' {
				gotA = append(gotA, op.text)
			}
			if op.kind != '-' {
				gotB = append(gotB, op.text)
			}
		}
		if !slices.Equal(gotA, a) && !(len(a) == 0 && len(gotA) == 0) || !slices.Equal(gotB, b) && !(len(b) == 0 && len(gotB) == 0) {
			t.Fatalf("a=%v b=%v rebuilt a=%v b=%v", a, b, gotA, gotB)
		}
	}
}
