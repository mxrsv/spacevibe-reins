//go:build unix

package main

import (
	"os"
	"testing"
)

// If the shell stops reading the core's stderr and closes it, a log line must not kill the core with SIGPIPE: after
// guardStdout fd 1 and fd 2 are the same pipe, and Go ends a program on a broken pipe on those two descriptors.
func TestCoreSurvivesAClosedStderr(t *testing.T) {
	c := prepareCoreIn(t, debugBin, t.TempDir())
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	c.cmd.Stderr = writer
	c.begin()
	writer.Close() // the parent's copy of the write end: the core holds the only one
	reader.Close() // nobody reads the log any more

	c.initialize()
	for _, id := range []string{"1", "2"} {
		// debug.panic logs "panic in debug.panic" and a stack to the broken stderr.
		c.wantError(c.call(id, "debug.panic", ""), -32603)
	}
	if r := c.call("3", "debug.slow", `{"ms":0}`); r.Error != nil {
		t.Fatalf("the core did not answer after its stderr closed: %+v", r.Error)
	}
	if code := c.waitExit(true); code != 0 {
		t.Fatalf("exit code %d", code)
	}
}
