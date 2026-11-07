package statusline

import (
	"errors"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/limits"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// maxSessionIDBytes is the longest session id a snapshot file may be named after.
const maxSessionIDBytes = 128

// Failure is a capture error with the fixed reason recorded for it. Its message is a fixed sentence.
type Failure struct {
	Reason string
	Err    coreerr.Error
}

func (f *Failure) Error() string { return f.Err.Error() }

func (f *Failure) Unwrap() error { return f.Err }

func fail(reason, message string) *Failure {
	return &Failure{Reason: reason, Err: coreerr.NewStatus(message, coreerr.StatusBadRequest)}
}

// ReasonOf is the reason code recorded for a capture error, or ReasonWriteFailed for any other.
func ReasonOf(err error) string {
	var f *Failure
	if errors.As(err, &f) {
		return f.Reason
	}
	return ReasonWriteFailed
}

// Capture stores the rate limits of one status line input as <data>/claude-limits/<session>.json
// (LimitsClaudeStatusline.capture). Nothing else of the input is kept: not the transcript path, not the rest of the
// payload. An input with no rate limits is normal before the first response and is not an error. Invalid input
// never replaces a good snapshot. The Failure it returns carries the reason for the last-error file.
func Capture(cfg config.Config, r roots.Roots, data []byte, now time.Time) error {
	if len(data) > limits.MaxInputBytes {
		return fail(ReasonInputTooLarge, "Status line input is too large.")
	}
	document, err := ojson.Parse(data)
	if err != nil {
		return fail(ReasonInvalidInput, "Status line input is not valid JSON.")
	}
	input := document.Root()
	session, _ := stringMember(input, "session_id")
	if session == "" || len(session) > maxSessionIDBytes || !limits.SessionIDSyntax(session) {
		return fail(ReasonInvalidInput, "Status line session identity is invalid.")
	}
	raw, ok := objectMember(input, "rate_limits")
	if !ok {
		return nil
	}
	parsed, err := limits.ParseWindows(raw)
	if err != nil {
		return &Failure{Reason: ReasonInvalidLimits, Err: asCoreError(err)}
	}
	if len(parsed) == 0 {
		return nil
	}
	account, ok := limits.AccountKey(r)
	if !ok {
		return fail(ReasonAccountUnknown, "Claude account could not be identified; capture skipped.")
	}
	folder, err := fsx.ManagedDirectory(cfg, r, limits.SnapshotDir)
	if err != nil {
		return &Failure{Reason: ReasonFolderRefused, Err: asCoreError(err)}
	}
	file := filepath.Join(folder, session+".json")
	// A session first captured under another account cannot relabel its old in-memory quota after a login switch.
	if old, ok := limits.ReadSnapshot(file); ok {
		if got, _ := stringMember(old, "account"); got != account {
			return nil
		}
	}
	var windows []ojson.Member
	for _, spec := range limits.StatuslineWindows() {
		window, ok := objectMember(raw, spec.Key)
		if !ok {
			continue
		}
		used, _ := window.Member("used_percentage")
		reset, _ := window.Member("resets_at")
		windows = append(windows, ojson.Member{Key: spec.Key, Value: ojson.Object(
			ojson.Member{Key: "used_percentage", Value: used}, ojson.Member{Key: "resets_at", Value: reset},
		)})
	}
	clean := ojson.Object(
		ojson.Member{Key: "account", Value: ojson.String(account)},
		ojson.Member{Key: "observedAt", Value: ojson.Number(seconds(now))},
		ojson.Member{Key: "rate_limits", Value: ojson.Object(windows...)},
	)
	text, err := ojson.Pretty(clean)
	if err != nil {
		return fail(ReasonWriteFailed, "The quota snapshot could not be written.")
	}
	if err := fsx.MkdirAll(folder, 0o700); err != nil {
		return &Failure{Reason: ReasonWriteFailed, Err: asCoreError(err)}
	}
	if err := fsx.AtomicWrite(file, []byte(text), 0o600, fsx.AtomicWriteOptions{}); err != nil {
		return &Failure{Reason: ReasonWriteFailed, Err: asCoreError(err)}
	}
	// Keep the newest MaxSessions snapshots. A file without an account string is not ours to delete.
	files := limits.SnapshotFiles(cfg, r)
	if len(files) > limits.MaxSessions {
		for _, old := range files[limits.MaxSessions:] {
			if snapshot, ok := limits.ReadSnapshot(old); ok {
				if _, isOurs := stringMember(snapshot, "account"); isOurs {
					if err := fsx.RemoveFile(old); err != nil {
						return &Failure{Reason: ReasonWriteFailed, Err: asCoreError(err)}
					}
				}
			}
		}
	}
	return nil
}

// seconds is the instant as seconds since 1970 in the spelling Swift's Double description gives ("1793900000.0").
func seconds(t time.Time) string {
	text := strconv.FormatFloat(float64(t.UnixMicro())/1e6, 'f', -1, 64)
	if !strings.Contains(text, ".") {
		text += ".0"
	}
	return text
}

// asCoreError keeps a safe message from the chain, or a fixed sentence when there is none.
func asCoreError(err error) coreerr.Error {
	if e, ok := coreerr.As(err); ok {
		return e
	}
	return coreerr.NewStatus("The quota snapshot could not be written.", coreerr.StatusInternalFailure)
}

// stringMember is a string member of an object (false for a missing key or another type).
func stringMember(v ojson.Value, key string) (string, bool) {
	value, ok := v.Member(key)
	if !ok {
		return "", false
	}
	return value.StringValue()
}

// objectMember is a member that is present and not JSON null (limitsMember in Swift).
func objectMember(v ojson.Value, key string) (ojson.Value, bool) {
	value, ok := v.Member(key)
	if !ok || value.Kind() == ojson.KindNull {
		return ojson.Value{}, false
	}
	return value, true
}
