package statusline

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/limits"
)

const (
	// shell runs the original command, the way Claude would have run it.
	shell = "/bin/sh"
	// readChunk is how much of stdin is read and forwarded at a time.
	readChunk = 64 * 1024
	// captureFailed is the one sentence a failed capture prints. It never says why: stderr is not a safe place for
	// input or error text. The reason goes to the last-error file.
	captureFailed = "Quota capture failed; the original status line is unchanged."
)

// runCapture is `statusline capture <data> <claudeRoot> <original>`. Claude starts it with the status line input on
// stdin. It runs <original> through /bin/sh -c, copies stdin to it and gives it this process's stdout and stderr, so
// the status line prints what it always did and the exit status is its own. While it does, it keeps the rate limits
// of the input (Capture). A capture error never reaches Claude's output beyond one fixed sentence on stderr.
//
// The original runs in Claude's process group, not a new one: cancelling the status line group also cancels it.
// Go's os/exec starts a new group only when SysProcAttr asks, which it does not here.
func runCapture(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) != 3 {
		report(stderr, "Invalid capture arguments.")
		return 1
	}
	data, claudeRoot, original := args[0], args[1], args[2]
	ignoreBrokenPipe()

	var child *exec.Cmd
	var feed *os.File
	if original != "" {
		child, feed = startOriginal(original, stdout, stderr)
		if child == nil {
			report(stderr, "Original status line could not start.")
		}
	}

	input, oversized, readErr := forward(stdin, feed)
	if feed != nil {
		_ = feed.Close()
	}

	if reason := collect(data, claudeRoot, input, oversized, readErr); reason != "" {
		report(stderr, captureFailed)
	}

	if child == nil {
		if original == "" {
			return 0
		}
		return 1
	}
	_ = child.Wait() // the status is read from the process state, whatever Wait says about copying
	if child.ProcessState == nil {
		return 1
	}
	return exitStatus(child.ProcessState)
}

// startOriginal starts `sh -c original` with a pipe for stdin and the given stdout and stderr (the process files
// themselves, passed on as descriptors, when they are *os.File). It returns the command and the write end of the
// pipe, or nil when the shell could not start.
func startOriginal(original string, stdout, stderr io.Writer) (*exec.Cmd, *os.File) {
	read, write, err := os.Pipe()
	if err != nil {
		return nil, nil
	}
	child := &exec.Cmd{Path: shell, Args: []string{"sh", "-c", original}, Stdin: read, Stdout: stdout, Stderr: stderr}
	err = child.Start()
	_ = read.Close()
	if err != nil {
		_ = write.Close()
		return nil, nil
	}
	return child, write
}

// forward copies stdin to feed (nil when there is no original, or once the original stopped reading) until the end
// of input, and keeps at most limits.MaxInputBytes of it for Capture. A longer input is forwarded whole but never
// kept (oversized). A write error ends forwarding and nothing else: the original may stop reading early, and
// the rest of stdin is still drained. A read error ends the input and is reported to the caller (G-fix.19: Swift
// abandoned the original at that point).
func forward(stdin io.Reader, feed *os.File) (kept []byte, oversized bool, readErr bool) {
	buffer := make([]byte, readChunk)
	for {
		n, err := stdin.Read(buffer)
		if n > 0 {
			chunk := buffer[:n]
			if feed != nil {
				if _, werr := feed.Write(chunk); werr != nil {
					feed = nil
				}
			}
			if !oversized && len(kept)+n <= limits.MaxInputBytes {
				kept = append(kept, chunk...)
			} else {
				oversized, kept = true, nil
			}
		}
		if err != nil {
			return kept, oversized, err != io.EOF
		}
	}
}

// collect resolves the roots the way Claude's environment names them, stores the capture and keeps the last-error
// file true. It returns the failure reason, or "" when the capture worked.
func collect(data, claudeRoot string, input []byte, oversized, readErr bool) string {
	cfg, err := config.Load()
	if err != nil || !filepath.IsAbs(data) {
		return ReasonRootsRefused // the environment or the data root argument is unusable; there is nowhere to record it
	}
	cfg.Home = data // the data folder is the one the wrapper names, whatever SPACEVIBE_HOME says here
	cfg, r, err := resolve(cfg)
	if err != nil {
		return ReasonRootsRefused
	}
	reason := ""
	switch {
	case readErr:
		reason = ReasonInputUnreadable
	case oversized:
		reason = ReasonInputTooLarge
	case filepath.Clean(r.Claude.Root) != filepath.Clean(claudeRoot):
		reason = ReasonClaudeRootChanged
	default:
		if err := Capture(cfg, r, input, time.Now()); err != nil {
			reason = ReasonOf(err)
		}
	}
	if reason == "" {
		clearFailure(cfg, r)
	} else {
		recordFailure(cfg, r, reason)
	}
	return reason
}
