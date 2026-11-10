package rules

import (
	"encoding/json"
	"strings"
	"testing"
)

// A proxy URL with a password in [permissions.x.network] never leaves the core with the password; the rest of the
// URL and the other flags stay as written.
func TestNetworkFlagPasswordNeverEscapes(t *testing.T) {
	sb := newSandbox(t)
	sb.write(".codex/config.toml", "[permissions.work.network]\nenabled = true\nproxy = \"http://bob:"+canary+"@proxy.corp:8080\"\nmode = \"limited\"\n")
	data, err := json.Marshal(ReadCodexPermissions(sb.r))
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	if strings.Contains(text, canary) {
		t.Fatalf("the proxy password escaped: %s", text)
	}
	for _, want := range []string{`"key":"proxy","value":"http://bob:•••@proxy.corp:8080"`, `"key":"mode","value":"limited"`, `"key":"enabled","value":true`} {
		if !strings.Contains(text, want) {
			t.Errorf("missing %s in %s", want, text)
		}
	}
}
