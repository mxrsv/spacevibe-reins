package identity

import (
	"strings"
	"testing"
)

func TestNamesShareOneIdentity(t *testing.T) {
	if EnvPrefix != strings.ToUpper(Name)+"_" {
		t.Fatalf("EnvPrefix %q does not match Name %q", EnvPrefix, Name)
	}
	if DataDir != "."+Name {
		t.Fatalf("DataDir %q does not match Name %q", DataDir, Name)
	}
	if Version == "" {
		t.Fatal("Version is empty")
	}
}
