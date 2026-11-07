// Package rules is the Claude Code permission rules of SpaceVibe: list the rules of a scope, add, remove and change a
// verdict, derive the capability grid, replace a grid cell, and read the Codex permission keys (read-only).
//
// Ported from Sources/ReinsCore/Rules*.swift (RulesTypes, RulesParse, RulesStore, RulesSettingsFile,
// RulesCapabilityWrite, RulesCapabilityGrid, RulesCodexPermissions) and, from Sources/SpaceVibe/Rules, RulesSnapshot.swift
// (what a snapshot assembles) and RulesScopes.swift (scrub, and the live check of a rule).
//
// # Two layers
//
// Store is the engine: its messages name the absolute settings file, as the golden expects. Service is the RPC
// surface: it validates params, keeps the project list of the process, and scrubs the settings-file path out of every
// message and problem (replacing it by the scope's label), because the shell must never see it.
//
// # Writes
//
// Every write is one mutate.WithLock whose body calls tx.EditJSON, so it is guarded, journaled and undoable, keeps
// every other key, the indent and the line endings, and takes the write lock exactly once (never nest a locking call).
// The capability plan is computed before the lock, as in Swift.
//
// # Not readable
//
// A settings file, project folder or Codex file that cannot be looked at (macOS privacy denial, no permission) reads
// as "not readable", never as "no rules" or as safe defaults (G-fix.1, G-fix.18). The golden projection selects fixed
// fields only, so the extra fields (NotReadable and friends) are outside it.
package rules
