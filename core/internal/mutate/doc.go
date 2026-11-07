// Package mutate is every write Reins makes to the CLIs' configuration: add, remove and copy
// skills, agents and hooks, the file edit they and the rules package share, the undo journal and
// the app trash.
//
// Ported from Sources/ReinsCore/Mutate.swift, MutateItems.swift, MutateHooks.swift,
// MutateHookEdit.swift (hook-edit.go), MutateText.swift (text.go), Journal.swift,
// JournalTrash.swift (trash.go), FileEdit.swift and the rollback logic of the mutation
// transaction (Journal.recordMutation, rollbackMutation).
//
// # Locks
//
// The Swift write lock was re-entrant; fsx.WithWriteLock is not. Every exported entry point takes
// the lock once (WithLock, or a package function that calls it) and runs a method of *Tx, which
// assumes the lock is held and never takes it. A *Tx exists only inside WithLock, so a caller
// (the rules package) that needs several steps under one lock gets them from the handle and cannot
// nest a locking call by mistake.
//
// # Files
//
// Every write goes through internal/fsx (atomic write, exclusive create, move with the EXDEV
// fallback, remove, link, folder create), so the real-home write guard (fsx.InstallWriteGuard)
// covers all of it. Nothing here calls os.WriteFile, os.Rename or os.Remove.
//
// # Journal
//
// <data>/journal.json is a JSON array, newest first, 200 entries, written with a 2-space layout and
// no trailing newline, the same file and entry shape the Swift engine writes. A journal that exists
// but is not a JSON array makes every write path refuse with 409 (fail closed), and History
// reports it instead of an empty list (G-fix.8). Undo checks every path in an entry against the
// folders Reins manages before it changes anything (G-fix.3, containment.go).
//
// # Not RPC
//
// AddSkill, AddAgent and AddHook are Go API only: the golden scenarios use them, but the app has
// no caller and the RPC methods are loadout.copyToOther, loadout.removeItem,
// loadout.removeDeadHooks, journal.undo and journal.history (Service). In particular AddHook is
// never exposed: it would write a Codex hook that Codex skips until it is trusted, which
// CopyToOther refuses for the same reason (G-fix.16).
package mutate
