package main

import (
	"path/filepath"
	"strconv"
	"testing"
)

// leakFiles are files no parser can read, each holding a token that must never come back out (S-R3). A token
// names its file, so a failure says which parse path leaked without printing anything else.
func leakFiles(home string) map[string]string {
	project := filepath.Join(home, "work", "proj")
	return map[string]string{
		".claude/settings.json":                    `{"apiKey": "LEAK-CLAUDE-SETTINGS", "permissions": {"allow": [}`,
		".claude/.claude.json":                     `{"oauthAccount": {"accountUuid": "LEAK-CLAUDE-STATE" `,
		".claude/projects/-work-proj/p1.jsonl":     `{"type":"user","cwd":` + strconv.Quote(project) + `,"timestamp":"2026-11-02T10:00:00.000Z"}` + "\n" + `{"type":"assistant","LEAK-CLAUDE-LOG": ` + "\n",
		"work/proj/.claude/settings.json":          `{"env": {"TOKEN": "LEAK-PROJECT-SETTINGS"}, `,
		"work/proj/.claude/settings.local.json":    `permissions = "LEAK-PROJECT-LOCAL"`,
		".codex/config.toml":                       "token = \"LEAK-CODEX-TOML\n[projects.\"/x\n sandbox_mode = ",
		".codex/hooks.json":                        `{"hooks": LEAK-CODEX-HOOKS`,
		".codex/rules/default.rules":               `prefix_rule(pattern=["LEAK-CODEX-RULES"], decision=`,
		".codex/sessions/2026/11/02/rollout.jsonl": `{"type":"event_msg","payload": LEAK-CODEX-ROLLOUT` + "\n",
		".spacevibe/journal.json":                  `{"LEAK-JOURNAL": `,
		".spacevibe/claude-limits/s1.json":         `{"LEAK-STATUSLINE": `,
	}
}

func leakTokens() []string {
	return []string{
		"LEAK-CLAUDE-SETTINGS", "LEAK-CLAUDE-STATE", "LEAK-CLAUDE-LOG", "LEAK-PROJECT-SETTINGS", "LEAK-PROJECT-LOCAL",
		"LEAK-CODEX-TOML", "LEAK-CODEX-HOOKS", "LEAK-CODEX-RULES", "LEAK-CODEX-ROLLOUT", "LEAK-JOURNAL", "LEAK-STATUSLINE",
	}
}

// leakCases is S-R3: a file that does not parse must not reach an error, a problem line or stderr, through any
// method or any one-shot command. It also checks that the failure paths were reached (an error or a problem line).
func leakCases(t *testing.T) {
	t.Run("leak_in_errors", func(t *testing.T) {
		c := startPlain(t, shippedBin)
		for rel, content := range leakFiles(c.home) {
			writeFile(t, filepath.Join(c.home, rel), content)
		}
		c.initialize()
		var invSnap struct{ Problems []string }
		decodeInto(t, c.ok(c.call("1", "inventory.read", `{}`)), &invSnap)
		if len(invSnap.Problems) == 0 {
			t.Fatal("inventory.read reported no problem for an unreadable settings file")
		}
		var snap struct {
			ProjectDirs []string `json:"projectDirs"`
			Problems    []string `json:"problems"`
		}
		decodeInto(t, c.ok(c.call("2", "rules.snapshot", `{"scope":"global","dir":null,"refreshProjects":true}`)), &snap)
		if len(snap.Problems) == 0 {
			t.Fatal("rules.snapshot reported no problem for an unreadable settings file")
		}
		if len(snap.ProjectDirs) != 1 {
			t.Fatalf("project discovery found %v", snap.ProjectDirs)
		}
		project := quote(snap.ProjectDirs[0])

		type call struct{ method, params string }
		calls := []call{
			{"loadout.rows", `{}`}, {"usage.scan", `{}`}, {"activity.read", `{}`}, {"limits.read", `{}`},
			{"rules.snapshot", `{"scope":"project","dir":` + project + `}`},
			{"rules.snapshot", `{"scope":"local","dir":` + project + `}`},
			{"rules.preview", `{"scope":"global","dir":null,"capability":"run","verdict":"deny"}`},
			{"rules.preview", `{"scope":"project","dir":` + project + `,"capability":"run","verdict":"deny"}`},
			{"rules.setCapability", `{"scope":"global","dir":null,"capability":"run","verdict":"deny"}`},
			{"rules.setCapability", `{"scope":"project","dir":` + project + `,"capability":"read","verdict":"allow"}`},
			{"rules.add", `{"scope":"global","dir":null,"verdict":"allow","rule":"Bash(ls)"}`},
			{"rules.add", `{"scope":"local","dir":` + project + `,"verdict":"allow","rule":"Bash(ls)"}`},
			{"rules.remove", `{"scope":"global","dir":null,"verdict":"allow","rule":"Bash(ls)"}`},
			{"rules.changeVerdict", `{"scope":"global","dir":null,"rule":"Bash(ls)","from":"allow","to":"deny"}`},
			{"loadout.removeDeadHooks", `{"cli":"claude"}`}, {"loadout.removeDeadHooks", `{"cli":"codex"}`},
			{"loadout.removeItem", `{"id":"claude:hook:0123456789ab"}`},
			{"loadout.copyToOther", `{"id":"claude:skill:user:nothing"}`},
			{"journal.history", `{}`}, {"journal.undo", `{"id":"00000000-0000-4000-8000-000000000000"}`},
			{"activity.stop", `{"cli":"claude","id":"nothing"}`},
		}
		for i, k := range calls {
			id := strconv.Itoa(10 + i)
			c.send(request(id, k.method, k.params)) // success or refusal: only the text matters here
			for {                                   // usage.scan sends progress first
				if r := parseReply(t, c.recv()); string(r.ID) == id {
					break
				}
			}
		}

		// Every error the shell saw is a fixed sentence, and the unreadable journal is refused, not read as empty.
		if got := c.status(c.call("50", "journal.history", `{}`)); got != 409 {
			t.Errorf("journal.history on an unreadable journal: status %d", got)
		}
		if got := c.status(c.call("51", "rules.add", `{"scope":"global","dir":null,"verdict":"allow","rule":"Bash(ls)"}`)); got != 409 {
			t.Errorf("rules.add on an unreadable settings file: status %d", got)
		}
		if code := c.waitExit(true); code != 0 {
			t.Fatalf("exit %d", code)
		}
		for _, r := range c.rec {
			if tok := contains(r.line, leakTokens()...); r.dir == "recv" && tok != "" {
				t.Errorf("a reply carries %s: %.200q", tok, r.line)
			}
		}
		if tok := contains(c.stderr.String(), leakTokens()...); tok != "" {
			t.Errorf("stderr carries %s", tok)
		}
		// The one-shot commands go through the same parse paths.
		for _, args := range [][]string{{"inventory"}, {"usage"}, {"activity"}, {"limits"}, {"rules"}, {"rules", "--dir", snap.ProjectDirs[0]}} {
			out, errOut, code := runBinary(t, shippedBin, homeEnv(c.home), append(args, "--json")...)
			if tok := contains(string(out)+string(errOut), leakTokens()...); tok != "" {
				t.Errorf("%v (exit %d) prints %s", args, code, tok)
			}
		}
	})
}
