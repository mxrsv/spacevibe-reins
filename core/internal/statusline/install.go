package statusline

import (
	"os"
	"path/filepath"

	"spacevibe.dev/core/internal/config"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/identity"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/ojson"
	"spacevibe.dev/core/internal/roots"
)

// binDir is the managed folder under the data root that holds the installed copy of this executable.
const binDir = "bin"

// InstallLabel is the journal label of the settings edit.
const InstallLabel = "Enable Claude limit capture"

// Executable is where install puts the copy of the executable that Claude runs: <data>/bin/spacevibe.
func Executable(r roots.Roots) string { return filepath.Join(r.Data, binDir, identity.Name) }

// WrapperCommand is the status line command that runs the original through capture. Every argument is one POSIX
// shell word; the original is the last, so it reaches /bin/sh -c byte for byte.
func WrapperCommand(r roots.Roots, original string) string {
	return Quote(Executable(r)) + " " + "statusline " + cmdCapture + " " + Quote(r.Data) + " " + Quote(r.Claude.Root) + " " + Quote(original)
}

// Install is explicit setup (StatuslineSetup.install): it copies binary, the running executable with its links
// resolved, to <data>/bin/spacevibe (a fresh copy on every call, so a reinstall refreshes it) and edits Claude's
// settings.json so statusLine.command runs the original command through capture. Every other settings member is
// kept. The entry is nil when the settings already carry this exact wrapper (a no-op); otherwise Undo restores the
// settings through the journal, with its conflict checks protecting later edits. Nothing is written when the
// current status line is not a command or when <data>/bin leaves the data root.
func Install(cfg config.Config, r roots.Roots, binary string) (*mutate.Entry, error) {
	folder, err := fsx.ManagedDirectory(cfg, r, binDir)
	if err != nil {
		return nil, err
	}
	// Everything that can be refused is checked before the first write: the source is read now, the settings edit
	// runs next, and the copy is written only after the edit has succeeded.
	payload, err := readExecutable(binary, Executable(r))
	if err != nil {
		return nil, err
	}
	entry, err := editSettings(r)
	if err != nil {
		return nil, err
	}
	if err := writeExecutable(folder, Executable(r), payload); err != nil {
		// The settings must never point at a copy that is not there: put them back.
		if entry != nil {
			_ = Undo(r, entry.ID)
		}
		return nil, err
	}
	return entry, nil
}

// editSettings is the settings.json half of Install.
func editSettings(r roots.Roots) (*mutate.Entry, error) {
	return mutate.EditJSON(r, r.Claude.HookFile, InstallLabel, nil, func(doc *ojson.Document) (*ojson.Document, error) {
		current, present := doc.Root().Member("statusLine")
		command := ""
		if present && current.Kind() != ojson.KindNull {
			kind, _ := stringMember(current, "type")
			text, hasCommand := stringMember(current, "command")
			if _, isObject := current.ObjectValue(); !isObject || kind != "command" || !hasCommand {
				return nil, coreerr.NewStatus("The current status line is unsupported; nothing was replaced.", coreerr.StatusConflict)
			}
			command = text
		}
		// Whatever wrapper is there, for any data root or either spelling, is replaced, never wrapped again.
		wanted := WrapperCommand(r, unwrap(command))
		if command == wanted {
			return doc, nil
		}
		var err error
		base := doc
		if present && current.Kind() == ojson.KindNull {
			if base, err = doc.Remove(ojson.Path("statusLine")); err != nil {
				return nil, err
			}
		}
		if base, err = base.Set(ojson.Path("statusLine", "type"), ojson.String("command")); err != nil {
			return nil, err
		}
		return base.Set(ojson.Path("statusLine", "command"), ojson.String(wanted))
	})
}

// Undo restores the settings an install changed, by journal id. The installed copy of the executable is kept.
func Undo(r roots.Roots, id string) error {
	_, err := mutate.Undo(r, id)
	return err
}

// readExecutable reads the executable to install. It is nil when source and destination are the same file: the copy
// is skipped.
func readExecutable(source, destination string) ([]byte, error) {
	if roots.ResolvedPath(source) == roots.ResolvedPath(destination) {
		return nil, nil
	}
	data, err := os.ReadFile(source)
	if err != nil {
		return nil, coreerr.NewStatus("The "+identity.Name+" executable could not be read to install it.", coreerr.StatusInternalFailure)
	}
	return data, nil
}

// writeExecutable writes the executable through a temp file and a rename, never in place: a capture that Claude
// started a moment ago may be running the old copy. A nil payload (installing from the installed copy) writes nothing.
func writeExecutable(folder, destination string, payload []byte) error {
	if payload == nil {
		return nil
	}
	if err := fsx.MkdirAll(folder, 0o700); err != nil {
		return err
	}
	return fsx.AtomicWrite(destination, payload, 0o700, fsx.AtomicWriteOptions{})
}
