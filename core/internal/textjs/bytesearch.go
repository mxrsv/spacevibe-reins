package textjs

import "bytes"

var toolUseIDKey = []byte(`"tool_use_id":"`)

// Contains reports whether needle occurs in haystack. Log lines are searched as bytes,
// as the Node code searched strings. An empty needle is always found.
func Contains(haystack []byte, needle string) bool {
	return bytes.Contains(haystack, []byte(needle))
}

// ToolUseIDs returns the [^"]+ values that follow every `"tool_use_id":"` in line, in
// order. A value that is empty or runs to the end of the line without a closing quote is skipped.
func ToolUseIDs(line []byte) []string {
	var out []string
	for i := 0; i+len(toolUseIDKey) <= len(line); {
		if !bytes.HasPrefix(line[i:], toolUseIDKey) {
			i++
			continue
		}
		start := i + len(toolUseIDKey)
		end := start
		for end < len(line) && line[end] != '"' {
			end++
		}
		if end > start && end < len(line) {
			out = append(out, Repair(string(line[start:end])))
		}
		i = max(end, i+1)
	}
	return out
}
