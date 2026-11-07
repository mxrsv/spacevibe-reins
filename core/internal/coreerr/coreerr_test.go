package coreerr

import (
	"errors"
	"fmt"
	"testing"
)

func TestDefaultsAndStatus(t *testing.T) {
	if e := New("bad"); e.Status != 400 || e.Error() != "bad" {
		t.Fatalf("New = %+v", e)
	}
	if e := NewStatus("gone", StatusNotFound); e.Status != 404 {
		t.Fatalf("NewStatus = %+v", e)
	}
	if New("a") != New("a") || New("a") == NewStatus("a", 409) {
		t.Fatal("Error must compare by message and status")
	}
}

func TestAsThroughWrapping(t *testing.T) {
	wrapped := fmt.Errorf("outer: %w", NewStatus("refused", StatusForbidden))
	e, ok := As(wrapped)
	if !ok || e.Status != 403 || e.Message != "refused" {
		t.Fatalf("As = %+v, %v", e, ok)
	}
	if _, ok := As(errors.New("plain")); ok {
		t.Fatal("a plain error is not a coreerr.Error")
	}
}
