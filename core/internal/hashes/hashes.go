// Package hashes holds the identity and content hashes the core writes into its output.
// Ported from Sources/ReinsCore/InventoryHash.swift (Sha1, Inventory.sha, Inventory.hookHash,
// Inventory.bare) and Sources/ReinsCore/JournalSHA256.swift (ContentHash.sha256Hex). The Swift
// files hand-wrote SHA-1 and SHA-256 because CryptoKit is Apple-only; Go has both in the
// standard library, so only the output formats are kept.
package hashes

import (
	"crypto/sha1" //nolint:gosec // identity only, never security: ids and hook identity in the logs
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

// shaHexLen is the number of hex digits Sha keeps: the first 6 bytes of the SHA-1.
const shaHexLen = 12

// SHA1Hex is the full lowercase hex SHA-1 (40 digits) of data.
func SHA1Hex(data []byte) string {
	sum := sha1.Sum(data) //nolint:gosec // identity only
	return hex.EncodeToString(sum[:])
}

// SHA256Hex is the lowercase hex SHA-256 (64 digits) of data, like Node's digest('hex').
// A journal entry stores it for the bytes an edit wrote, and undo compares against it.
func SHA256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// Sha is the first 12 hex digits of the SHA-1 of the text's bytes. Hook ids, project ids and
// hook identity are built from it. Go strings hold raw bytes, so a string that is not valid
// UTF-8 hashes as is, where Swift strings are always valid UTF-8 by construction.
func Sha(text string) string {
	return SHA1Hex([]byte(text))[:shaHexLen]
}

// HookHash is the identity of a hook in the logs: event plus command, joined by "|".
// Hashing the command alone inflates run counts.
func HookHash(event, command string) string {
	return Sha(event + "|" + command)
}

// Bare is the part after the last ":" of a plugin-qualified name ("plugin:skill" -> "skill").
// A name without ":" is returned as is; a trailing ":" gives "".
func Bare(name string) string {
	return name[strings.LastIndexByte(name, ':')+1:]
}
