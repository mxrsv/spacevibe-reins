//go:build osusergo

package roots

// With the osusergo tag, os/user stops calling getpwuid_r on darwin and falls back to $HOME, which
// would void the AC3 real-home guard (H1). Refuse to build rather than guard nothing.
var _ = osusergoVoidsTheRealHomeGuard
