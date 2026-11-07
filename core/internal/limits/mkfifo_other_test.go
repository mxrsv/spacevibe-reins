//go:build !unix

package limits

import "testing"

func mkfifo(t *testing.T, path string) {
	t.Helper()
	t.Skip("no FIFOs on this platform")
}
