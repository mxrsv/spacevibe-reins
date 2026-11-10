package inventory

import (
	"encoding/json"
	"strings"
	"testing"
)

// The wire shows a hook command with its credentials masked; the inventory item keeps the raw command, because a
// copy or a removal finds the hook by that text, and the hash is made from it.
func TestHookCommandIsMaskedOnTheWireOnly(t *testing.T) {
	const raw = "TOKEN=abc123 notify --url https://u:pw@h.dev"
	h := newTempHome(t)
	h.write(".claude/settings.json", hookConfig("Stop", raw))
	inv := Read(h.roots())
	if len(inv.Hooks) != 1 || inv.Hooks[0].Command != raw {
		t.Fatalf("the item must carry the raw command: %+v", inv.Hooks)
	}
	data, err := json.Marshal(inv)
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	for _, leak := range []string{"abc123", "pw@"} {
		if strings.Contains(text, leak) {
			t.Errorf("%q escaped: %s", leak, text)
		}
	}
	if !strings.Contains(text, `"command":"TOKEN=•••`) || !strings.Contains(text, `"hash":"`+inv.Hooks[0].Hash+`"`) {
		t.Errorf("wire = %s", text)
	}
}
