package goldentest

import (
	"fmt"
	"strings"
)

const (
	diffContext     = 3
	maxEditDistance = 2000 // more inserted plus deleted lines than this are shown as one removed/added block
)

type diffOp struct {
	kind byte // ' ' kept, '-' only in want, '+' only in got
	text string
}

// UnifiedDiff compares two texts line by line and returns a unified diff (three lines of context), or ""
// when they are equal. wantName and gotName label the "---" and "+++" lines. It is a small standard-library
// implementation for test failure output, not a patch generator: the common head and tail are cut off, and the
// differing middle is aligned by longest common subsequence; a middle too large for that is shown as one
// block of removed then added lines.
func UnifiedDiff(wantName, gotName, want, got string) string {
	if want == got {
		return ""
	}
	a, b := splitLines(want), splitLines(got)
	ops := diffOps(a, b)

	var out strings.Builder
	fmt.Fprintf(&out, "--- %s\n+++ %s\n", wantName, gotName)

	// lineA[i], lineB[i] are the 1-based line numbers at op i on each side.
	lineA, lineB := make([]int, len(ops)+1), make([]int, len(ops)+1)
	lineA[0], lineB[0] = 1, 1
	for i, op := range ops {
		lineA[i+1], lineB[i+1] = lineA[i], lineB[i]
		if op.kind != '+' {
			lineA[i+1]++
		}
		if op.kind != '-' {
			lineB[i+1]++
		}
	}

	for i := 0; i < len(ops); {
		if ops[i].kind == ' ' {
			i++
			continue
		}
		// A hunk runs from diffContext kept lines before the first change to diffContext after the last one;
		// changes closer than twice that share a hunk.
		start := max(0, i-diffContext)
		last, j := i, i
		for j < len(ops) && j-last <= 2*diffContext {
			if ops[j].kind != ' ' {
				last = j
			}
			j++
		}
		end := min(len(ops), last+1+diffContext)
		na, nb := lineA[end]-lineA[start], lineB[end]-lineB[start]
		firstA, firstB := lineA[start], lineB[start]
		if na == 0 { // an empty side starts at the line before, as diff -u prints it
			firstA--
		}
		if nb == 0 {
			firstB--
		}
		fmt.Fprintf(&out, "@@ -%d,%d +%d,%d @@\n", firstA, na, firstB, nb)
		for _, op := range ops[start:end] {
			out.WriteByte(op.kind)
			out.WriteString(op.text)
			out.WriteByte('\n')
		}
		i = end
	}
	return out.String()
}

func splitLines(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(strings.TrimSuffix(s, "\n"), "\n")
}

func diffOps(a, b []string) []diffOp {
	head := 0
	for head < len(a) && head < len(b) && a[head] == b[head] {
		head++
	}
	tail := 0
	for tail < len(a)-head && tail < len(b)-head && a[len(a)-1-tail] == b[len(b)-1-tail] {
		tail++
	}
	ma, mb := a[head:len(a)-tail], b[head:len(b)-tail]

	var ops []diffOp
	for _, s := range a[:head] {
		ops = append(ops, diffOp{' ', s})
	}
	ops = append(ops, middleOps(ma, mb)...)
	for _, s := range a[len(a)-tail:] {
		ops = append(ops, diffOp{' ', s})
	}
	return ops
}

// middleOps aligns two line lists with Myers' O(ND) algorithm, so a handful of edits in a huge file is cheap.
// Past maxEditDistance edits it gives up on alignment and returns every a line removed, then every b line added.
func middleOps(a, b []string) []diffOp {
	if ops, ok := myers(a, b); ok {
		return ops
	}
	ops := make([]diffOp, 0, len(a)+len(b))
	for _, s := range a {
		ops = append(ops, diffOp{'-', s})
	}
	for _, s := range b {
		ops = append(ops, diffOp{'+', s})
	}
	return ops
}

func myers(a, b []string) ([]diffOp, bool) {
	n, m := len(a), len(b)
	limit := min(maxEditDistance, n+m)
	offset := limit + 1
	v := make([]int32, 2*limit+3) // v[offset+k] is the furthest x on diagonal k = x - y
	var trace [][]int32           // trace[d] is v before round d
	final := -1
	for d := 0; d <= limit && final < 0; d++ {
		trace = append(trace, append([]int32(nil), v...))
		for k := -d; k <= d; k += 2 {
			var x int
			if k == -d || (k != d && v[offset+k-1] < v[offset+k+1]) {
				x = int(v[offset+k+1]) // step down: an insertion from b
			} else {
				x = int(v[offset+k-1]) + 1 // step right: a deletion from a
			}
			y := x - k
			for x < n && y < m && a[x] == b[y] {
				x, y = x+1, y+1
			}
			v[offset+k] = int32(x)
			if x >= n && y >= m {
				final = d
				break
			}
		}
	}
	if final < 0 {
		return nil, false
	}
	var rev []diffOp
	x, y := n, m
	for d := final; d > 0; d-- {
		pv := trace[d]
		k := x - y
		prevK := k - 1
		if k == -d || (k != d && pv[offset+k-1] < pv[offset+k+1]) {
			prevK = k + 1
		}
		prevX := int(pv[offset+prevK])
		prevY := prevX - prevK
		midX, midY := prevX+1, prevY // the point after the one edit of this round
		if prevK == k+1 {
			midX, midY = prevX, prevY+1
		}
		for x > midX && y > midY {
			rev = append(rev, diffOp{' ', a[x-1]})
			x, y = x-1, y-1
		}
		if prevK == k+1 {
			rev = append(rev, diffOp{'+', b[prevY]})
		} else {
			rev = append(rev, diffOp{'-', a[prevX]})
		}
		x, y = prevX, prevY
	}
	for x > 0 && y > 0 { // the leading diagonal of round 0
		rev = append(rev, diffOp{' ', a[x-1]})
		x, y = x-1, y-1
	}
	ops := make([]diffOp, len(rev))
	for i, op := range rev {
		ops[len(rev)-1-i] = op
	}
	return ops, true
}
