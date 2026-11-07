package rules

import (
	"os"
	"regexp"
	"slices"
	"strings"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/textjs"
)

// rules/*.rules of Codex: counts of prefix_rule(...) per decision, never the patterns.
var (
	ruleStart = regexp.MustCompile(`\bprefix_rule` + jsSpace + `*\(`)
	decision  = regexp.MustCompile(`decision` + jsSpace + `*=` + jsSpace + `*["']([A-Za-z0-9_]+)["']`)
)

// maxRulesFileBytes is how much of a .rules file is read (InventoryFileIO.maxTextBytes).
const maxRulesFileBytes = 1 << 20

func summarizeRules(folder string) RulesSummary {
	var out RulesSummary
	switch fsx.PathPresence(folder) {
	case fsx.Missing:
		return out
	case fsx.Unknown:
		out.FolderNotReadable = true
		return out
	}
	entries, err := os.ReadDir(folder)
	if err != nil {
		out.FolderNotReadable = true
		return out
	}
	names := make([]string, 0, len(entries))
	for _, e := range entries {
		names = append(names, e.Name())
	}
	slices.Sort(names)
	for _, name := range names {
		if !strings.HasSuffix(name, ".rules") {
			continue
		}
		data, err := readCapped(join(folder, name), maxRulesFileBytes)
		if err != nil {
			out.Unreadable++
			continue
		}
		out.Files++
		// Whole-line comments are dropped; a "#" after code is left alone, as in Node.
		var kept []string
		for _, line := range strings.Split(textjs.Repair(string(data)), "\n") {
			line = strings.TrimSuffix(line, "\r")
			if !strings.HasPrefix(jsTrimStart(line), "#") {
				kept = append(kept, line)
			}
		}
		code := strings.Join(kept, "\n")
		starts := ruleStart.FindAllStringIndex(code, -1)
		for i, match := range starts {
			end := len(code)
			if i+1 < len(starts) {
				end = starts[i+1][0]
			}
			verdict := "allow"
			if found := decision.FindStringSubmatch(code[match[1]:end]); found != nil {
				verdict = found[1]
			}
			switch verdict {
			case "allow":
				out.Allow++
			case "prompt":
				out.Prompt++
			case "forbidden":
				out.Forbidden++
			default:
				out.Other++
			}
		}
	}
	return out
}
