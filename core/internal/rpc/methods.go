// Package rpc is the NDJSON JSON-RPC 2.0 server the shell talks to over stdio. The written
// contract is docs/internals/core-protocol.md; this package follows it, including its `(new)`
// decisions. It has no Swift source: the Swift app calls the engine in process.
//
// The package holds the transport only. Domain methods are registered by the caller on a Registry.
package rpc

// Protocol limits and version (docs/internals/core-protocol.md, "Framing and lifecycle").
const (
	// ProtocolVersion is the integer the handshake must carry.
	ProtocolVersion = 1
	// MaxRequestLine is the longest request line, without its newline, in bytes.
	MaxRequestLine = 1 << 20
	// MaxResponseLine is the longest response line, without its newline, in bytes.
	MaxResponseLine = 64 << 20
)

// MethodInitialize is the handshake method, the only one allowed first.
const MethodInitialize = "initialize"

// MethodCancel is the shell-to-core notification that cancels a running request.
const MethodCancel = "$/cancelRequest"

// AllMethods is every method the finished core registers, in the order of the method table in the
// doc. TestDocMethodTable holds the doc to this list; each wiring task later asserts that the
// registered set equals it.
var AllMethods = []string{
	"initialize",
	"inventory.read",
	"usage.scan",
	"loadout.rows",
	"activity.read",
	"activity.subscribe",
	"activity.unsubscribe",
	"activity.stop",
	"loadout.copyToOther",
	"loadout.removeItem",
	"loadout.removeDeadHooks",
	"journal.undo",
	"journal.history",
	"rules.snapshot",
	"rules.preview",
	"rules.setCapability",
	"rules.add",
	"rules.remove",
	"rules.changeVerdict",
	"rules.check",
	"limits.read",
}
