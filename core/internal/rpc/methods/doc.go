// Package methods registers the domain methods of docs/internals/core-protocol.md on an rpc.Registry. It
// has no Swift source: the Swift app calls the engine in process.
//
// New builds the services once from a validated config; Register adds every method of rpc.AllMethods
// except `initialize`, which the server owns. Run calls the read-only handlers without a server, so the
// one-shot `--json` commands print exactly the object the RPC method returns.
//
// Rules for every handler here:
//   - params decode through rpc.DecodeParams, so an unknown member or a wrong type is -32602;
//   - errors pass through unchanged: a coreerr.Error becomes -32000 {status, message}, anything else is the
//     fixed -32603 (the type, never the text, goes to the log: S-R3);
//   - nothing is retried, and no handler holds the write lock: the services take it around their own write;
//   - there is no route to statusline capture or to AddHook, AddSkill and AddAgent.
package methods
