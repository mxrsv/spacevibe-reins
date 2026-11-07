package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"spacevibe.dev/core/internal/goldentest"
	"spacevibe.dev/core/internal/rpc"
)

// readCases are the contract cases of the read methods. Each runs the shipped binary over stdio.
func readCases(t *testing.T) {
	t.Run("rpc_cannot_capture", func(t *testing.T) {
		c := startCore(t, shippedBin)
		methods := methodsOf(t, c.initialize().Result)
		want := slices.Sorted(slices.Values(rpc.AllMethods))
		if !slices.Equal(methods, want) {
			t.Fatalf("the shipped binary registers %v, want exactly %v", methods, want)
		}
		for _, m := range methods {
			lower := strings.ToLower(m)
			if strings.HasPrefix(lower, "statusline") || strings.Contains(lower, "capture") || strings.Contains(lower, "addhook") ||
				strings.Contains(lower, "addskill") || strings.Contains(lower, "addagent") || strings.HasPrefix(lower, "debug.") {
				t.Errorf("method %q must not exist: capture runs a recorded command, and Add* are not methods", m)
			}
		}
		for _, m := range []string{"statusline.capture", "statusline.install", "loadout.addHook", "loadout.addSkill", "loadout.addAgent"} {
			c.wantError(c.call("9", m, `{}`), -32601)
		}
		c.finish("rpc_cannot_capture")
	})

	t.Run("inventory_read", func(t *testing.T) {
		home, data := sharedHome(t)
		c := startOn(t, shippedBin, home, data...)
		c.initialize()
		raw := c.ok(c.call("1", "inventory.read", `{}`))
		var snap struct {
			Items []map[string]any `json:"items"`
			Hooks []map[string]any `json:"hooks"`
			Roots map[string]string
		}
		decodeInto(t, raw, &snap)
		g, err := goldentest.LoadGolden("inventory")
		if err != nil {
			t.Fatal(err)
		}
		inv := g.(map[string]any)["inventory"].(map[string]any)
		if len(snap.Items) != len(inv["items"].([]any)) || len(snap.Hooks) != len(inv["hooks"].([]any)) {
			t.Fatalf("%d items and %d hooks, the golden has %d and %d", len(snap.Items), len(snap.Hooks), len(inv["items"].([]any)), len(inv["hooks"].([]any)))
		}
		for _, it := range snap.Items {
			if _, has := it["cells"]; has {
				t.Fatal("inventory.read must not carry cells")
			}
		}
		for _, h := range snap.Hooks {
			if u, has := h["usage"]; !has || u != nil {
				t.Fatalf("hook usage must be present and null, got %v", u)
			}
		}
		if snap.Roots["claude"] != c.home+"/.claude" {
			t.Fatalf("roots %v", snap.Roots)
		}
		c.wantError(c.call("2", "inventory.read", `{"refresh":true}`), -32602)
		c.wantError(c.call("3", "inventory.read", `[]`), -32602)
		c.finish("inventory_read")
	})

	t.Run("usage_scan_progress", func(t *testing.T) {
		home, data := sharedHome(t)
		c := startOn(t, shippedBin, home, data...)
		c.initialize()
		c.send(request("7", "usage.scan", `{}`))
		var last struct{ Done, Total int }
		var n int
		for {
			line := c.recv()
			if !strings.Contains(line, `"method":"usage/progress"`) {
				r := parseReply(t, line)
				if string(r.ID) != "7" || r.Error != nil {
					t.Fatalf("scan ended with %s", line)
				}
				var res struct {
					Files    int
					Sessions map[string]int
				}
				decodeInto(t, r.Result, &res)
				if res.Files == 0 || res.Files != last.Total || last.Done != last.Total || n == 0 {
					t.Fatalf("progress ended at %+v after %d notifications, result has %d files", last, n, res.Files)
				}
				break
			}
			var note struct {
				Params struct {
					ID          json.RawMessage `json:"id"`
					Done, Total int
				} `json:"params"`
			}
			decodeInto(t, json.RawMessage(line), &note)
			if string(note.Params.ID) != "7" || note.Params.Done < last.Done || note.Params.Done > note.Params.Total {
				t.Fatalf("bad progress %s", line)
			}
			last.Done, last.Total = note.Params.Done, note.Params.Total
			n++
		}
		// The result is the process's usage state now.
		var rows struct{ Usage string }
		decodeInto(t, c.ok(c.call("8", "loadout.rows", `{}`)), &rows)
		if rows.Usage != "ready" {
			t.Fatalf("usage state %q after a scan", rows.Usage)
		}
		c.finish("usage_scan_progress")
	})

	t.Run("usage_scan_busy_and_cancel", func(t *testing.T) {
		c := startCore(t, shippedBin)
		bulk := filepath.Join(c.home, ".claude", "projects", "-work-bulk")
		line := `{"type":"assistant","timestamp":"2026-11-02T10:00:00.000Z","sessionId":"s","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"ponytail"}}]}}` + "\n"
		for i := 0; i < 3000; i++ {
			writeFile(t, filepath.Join(bulk, "s"+strconv.Itoa(i)+".jsonl"), line)
		}
		c.initialize()
		// A cancelled scan answers -32800, stores nothing and leaves the cache as it was (absent).
		c.send(request("1", "usage.scan", `{}`))
		c.send(`{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}`)
		for {
			line := c.recv()
			if strings.Contains(line, `"method":"usage/progress"`) {
				continue
			}
			c.wantError(parseReply(t, line), -32800)
			break
		}
		if _, err := os.Stat(filepath.Join(c.home, ".spacevibe", "usage-cache.json")); err == nil {
			t.Fatal("a cancelled scan wrote the cache")
		}
		var rows struct{ Usage string }
		decodeInto(t, c.ok(c.call("2", "loadout.rows", `{}`)), &rows)
		if rows.Usage != "scanning" {
			t.Fatalf("a cancelled scan changed the usage state to %q", rows.Usage)
		}
		// Two scans at once: exactly one is refused with 409.
		c.send(request("3", "usage.scan", `{}`))
		c.send(request("4", "usage.scan", `{}`))
		busy, done := 0, 0
		for done < 2 {
			line := c.recv()
			if strings.Contains(line, `"method":"usage/progress"`) {
				continue
			}
			done++
			if r := parseReply(t, line); r.Error != nil {
				if got := c.status(r); got != 409 {
					t.Fatalf("status %d", got)
				}
				busy++
			}
		}
		if busy != 1 {
			t.Fatalf("%d scans were refused, want 1", busy)
		}
		c.end() // progress lines interleave with the replies, so there is no fixed transcript
	})

	t.Run("activity_subscribe_snapshot", func(t *testing.T) {
		t.Parallel()
		c := startPlain(t, shippedBin)
		writeFile(t, activityLog(c.home), editLine(activitySession, "/work/app/src/a.ts", 5))
		c.initialize()
		read := c.ok(c.call("1", "activity.read", `{}`))
		snap := c.ok(c.call("2", "activity.subscribe", `{}`))
		if string(read) != string(snap) {
			t.Fatalf("subscribe did not return the full report activity.read returns:\n%s\n%s", read, snap)
		}
		if got := reportFiles(t, snap); !slices.Equal(got, []string{"/work/app/src/a.ts"}) {
			t.Fatalf("files %v", got)
		}
		c.expectNone(rpcPollSlack) // nothing changed: the core stays silent through a whole poll
		if got := string(c.ok(c.call("3", "activity.unsubscribe", `{}`))); got != "{}" {
			t.Fatalf("unsubscribe returned %s", got)
		}
		if got := string(c.ok(c.call("4", "activity.unsubscribe", `{}`))); got != "{}" { // idempotent
			t.Fatalf("second unsubscribe returned %s", got)
		}
		// Unsubscribed: a change is not pushed.
		appendFile(t, activityLog(c.home), editLine(activitySession, "/work/app/src/b.ts", 6))
		c.expectNone(rpcPollSlack)
		c.wantError(c.call("5", "activity.subscribe", `{"every":1}`), -32602)
		c.finish("activity_subscribe_snapshot") // EOF stops the watchers: no line after the session
	})

	t.Run("activity_notification_on_change", func(t *testing.T) {
		t.Parallel()
		c := startPlain(t, shippedBin)
		writeFile(t, activityLog(c.home), editLine(activitySession, "/work/app/src/a.ts", 5))
		c.initialize()
		before := c.ok(c.call("1", "activity.subscribe", `{}`))
		appendFile(t, activityLog(c.home), editLine(activitySession, "/work/app/src/b.ts", 6))
		start := time.Now()
		line := c.recv() // within recvTimeout, three polls at most
		if d := time.Since(start); d > 8*time.Second {
			t.Fatalf("the notification took %v", d)
		}
		var note struct {
			Method string          `json:"method"`
			ID     json.RawMessage `json:"id"`
			Params json.RawMessage `json:"params"`
		}
		decodeInto(t, json.RawMessage(line), &note)
		if note.Method != "activity/report" || len(note.ID) != 0 {
			t.Fatalf("got %.200s", line)
		}
		if got := reportFiles(t, note.Params); !slices.Equal(got, []string{"/work/app/src/a.ts", "/work/app/src/b.ts"}) {
			t.Fatalf("pushed files %v (before: %v)", got, reportFiles(t, before))
		}
		// A second subscribe replaces the first and answers with a fresh full snapshot.
		again := c.ok(c.call("2", "activity.subscribe", `{}`))
		if string(again) != string(note.Params) {
			t.Fatalf("the re-subscribe snapshot differs from the last pushed report")
		}
		c.finish("activity_notification_on_change")
	})

	t.Run("activity_resync_after_restart", func(t *testing.T) {
		t.Parallel()
		first := startPlain(t, shippedBin)
		writeFile(t, activityLog(first.home), editLine(activitySession, "/work/app/src/a.ts", 5))
		first.initialize()
		old := first.ok(first.call("1", "activity.subscribe", `{}`))
		if code := first.waitExit(true); code != 0 { // EOF ends the session; the subscription dies with the process
			t.Fatalf("first core exit %d, stderr: %s", code, first.stderr.String())
		}
		// A change happens while no core runs.
		appendFile(t, activityLog(first.home), editLine(activitySession, "/work/app/src/b.ts", 6))
		second := startCoreIn(t, shippedBin, first.home)
		second.norm = newNormalizer(second.home)
		second.initialize()
		snap := second.ok(second.call("1", "activity.subscribe", `{}`))
		if got := reportFiles(t, snap); !slices.Equal(got, []string{"/work/app/src/a.ts", "/work/app/src/b.ts"}) {
			t.Fatalf("the fresh snapshot lists %v (the old one listed %v)", got, reportFiles(t, old))
		}
		second.finish("activity_resync_after_restart")
	})

	t.Run("stop_refuses_unknown", func(t *testing.T) {
		t.Parallel()
		c := startPlain(t, shippedBin)
		c.initialize()
		for i, p := range []struct {
			params string
			status int
		}{
			{`{"cli":"claude","id":"no-such-session"}`, 404},
			{`{"cli":"codex","id":"no-such-thread"}`, 404},
			{`{"cli":"codex","id":"pid:424242:1793620800000"}`, 404},
			{`{"cli":"codex","id":"pid:424242:unknown"}`, 404}, // an id ending :unknown cannot authorize a stop
			{`{"cli":"gemini","id":"x"}`, 400},
			{`{"cli":"claude","id":""}`, 400},
		} {
			if got := c.status(c.call(strconv.Itoa(i+1), "activity.stop", p.params)); got != p.status {
				t.Errorf("%s: status %d, want %d", p.params, got, p.status)
			}
		}
		// There is no pid parameter, whatever the shell sends.
		c.wantError(c.call("20", "activity.stop", `{"cli":"claude","id":"x","pid":1}`), -32602)
		c.wantError(c.call("21", "activity.stop", `{"cli":"claude","pid":1}`), -32602)
		c.wantError(c.call("22", "activity.stop", `{"cli":5,"id":"x"}`), -32602)
		c.finish("stop_refuses_unknown")
	})

	t.Run("limits_read", func(t *testing.T) {
		home := copiedHome(t)
		// A Claude usage cache with a window that resets far in the future, so it is current whatever the clock says.
		writeFile(t, filepath.Join(home, ".claude", ".claude.json"), `{"cachedUsageUtilization":{"fetchedAtMs":1793500000250,"utilization":{"limits":[`+
			`{"kind":"weekly_all","group":"weekly","percent":8,"severity":"normal","resets_at":"2099-11-06T16:00:00+00:00","scope":null,"is_active":true}]}}}`)
		c := startOn(t, shippedBin, home)
		c.initialize()
		var res struct {
			Limits []struct {
				CLI     string `json:"cli"`
				State   string `json:"state"`
				Windows []struct {
					ID      string  `json:"id"`
					Current bool    `json:"current"`
					Used    float64 `json:"usedPercent"`
				} `json:"windows"`
			} `json:"limits"`
		}
		decodeInto(t, c.ok(c.call("1", "limits.read", `{}`)), &res)
		var order []string
		for _, l := range res.Limits {
			order = append(order, l.CLI)
			if l.Windows == nil {
				t.Errorf("%s: windows must be an array", l.CLI)
			}
		}
		if !slices.Equal(order, []string{"claude", "codex", "gemini"}) {
			t.Fatalf("order %v", order)
		}
		claude := res.Limits[0]
		if claude.State != "measured" || len(claude.Windows) != 1 || claude.Windows[0].ID != "weekly_all" || !claude.Windows[0].Current || claude.Windows[0].Used != 8 {
			t.Fatalf("claude: %+v", claude)
		}
		c.wantError(c.call("2", "limits.read", `{"force":true}`), -32602)
		c.finish("limits_read")
	})

	t.Run("rules_snapshot", func(t *testing.T) {
		home, data := sharedHome(t)
		c := startOn(t, shippedBin, home, data...)
		c.initialize()
		var snap struct {
			ProjectDirs []string       `json:"projectDirs"`
			Scope       string         `json:"scope"`
			Dir         *string        `json:"dir"`
			FileLabel   string         `json:"fileLabel"`
			Exists      bool           `json:"exists"`
			NotReadable bool           `json:"notReadable"`
			Rules       []any          `json:"rules"`
			Grid        []any          `json:"grid"`
			Codex       map[string]any `json:"codex"`
		}
		decodeInto(t, c.ok(c.call("1", "rules.snapshot", `{"scope":"global","dir":null}`)), &snap)
		if snap.Scope != "global" || snap.Dir != nil || !snap.Exists || snap.NotReadable || len(snap.Grid) != 6 || len(snap.Rules) == 0 ||
			snap.FileLabel != "~/.claude/settings.json" || snap.Codex["present"] != true {
			t.Fatalf("global snapshot: %+v", snap)
		}
		for _, key := range []string{"notReadable", "skippedLines", "rules", "warnings"} {
			if _, has := snap.Codex[key]; !has {
				t.Errorf("codex lacks %q", key)
			}
		}
		// An absolute folder that discovery did not find falls back to the global scope, as the Swift screen does.
		decodeInto(t, c.ok(c.call("2", "rules.snapshot", `{"scope":"project","dir":"/nowhere/at/all","refreshProjects":true}`)), &snap)
		if snap.Scope != "global" || snap.Dir != nil {
			t.Fatalf("unknown project: scope %q dir %v", snap.Scope, snap.Dir)
		}
		if got := c.status(c.call("3", "rules.snapshot", `{"scope":"project","dir":"relative/dir"}`)); got != 400 {
			t.Errorf("relative dir: %d", got)
		}
		if got := c.status(c.call("4", "rules.snapshot", `{"scope":"global","dir":"/x"}`)); got != 400 {
			t.Errorf("global with a dir: %d", got)
		}
		if got := c.status(c.call("5", "rules.snapshot", `{"scope":"nope","dir":null}`)); got != 400 {
			t.Errorf("unknown scope: %d", got)
		}
		for i, m := range []string{
			`"method":"rules.add","params":{"scope":"project","dir":"/nowhere/at/all","verdict":"allow","rule":"Bash(ls)"}`,
			`"method":"rules.setCapability","params":{"scope":"local","dir":"/nowhere/at/all","capability":"run","verdict":"deny"}`,
			`"method":"rules.preview","params":{"scope":"project","dir":"/nowhere/at/all","capability":"run","verdict":"deny"}`,
		} { // a write can never aim at a folder discovery did not find
			c.send(`{"jsonrpc":"2.0","id":` + strconv.Itoa(30+i) + `,` + m + `}`)
			if got := c.status(c.reply(strconv.Itoa(30 + i))); got != 404 {
				t.Errorf("%s: status %d, want 404", m, got)
			}
		}
		c.wantError(c.call("6", "rules.snapshot", `{"scope":5,"dir":null}`), -32602)
		c.wantError(c.call("7", "rules.snapshot", `{"scope":"global","dir":null,"verdict":"allow"}`), -32602)
		var check struct {
			Valid   bool    `json:"valid"`
			Message *string `json:"message"`
		}
		decodeInto(t, c.ok(c.call("8", "rules.check", `{"rule":"Bash(git status)"}`)), &check)
		if !check.Valid || check.Message != nil {
			t.Fatalf("a good rule: %+v", check)
		}
		decodeInto(t, c.ok(c.call("9", "rules.check", `{"rule":"not a rule"}`)), &check)
		if check.Valid || check.Message == nil {
			t.Fatalf("a bad rule: %+v", check)
		}
		c.finish("rules_snapshot")
	})
}

// rpcPollSlack is a little more than one 3 s poll of an Activity subscription.
const rpcPollSlack = 3600 * time.Millisecond
