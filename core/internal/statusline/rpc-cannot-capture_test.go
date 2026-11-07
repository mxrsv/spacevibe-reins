package statusline

import (
	"slices"
	"strings"
	"testing"

	"spacevibe.dev/core/internal/rpc"
)

// rpc_cannot_capture (plan G2.6, D-3): capture runs a recorded shell command, so the app must have no way to start
// it. Claude is the only caller; the RPC method list has no statusline method and no way to capture. The shipped
// binary registers a subset of rpc.AllMethods (cmd/spacevibe TestContract/handshake_ok checks that), so the list is
// the whole surface. The wiring step can move this case into TestContract.
func TestRPCCannotCapture(t *testing.T) {
	t.Run("rpc_cannot_capture", func(t *testing.T) {
		for _, name := range rpc.AllMethods {
			lower := strings.ToLower(name)
			if strings.HasPrefix(lower, "statusline") || strings.Contains(lower, "capture") {
				t.Errorf("rpc.AllMethods has %q: the RPC surface must not reach statusline capture", name)
			}
		}
		if slices.Contains(rpc.AllMethods, "statusline.capture") {
			t.Error("statusline.capture is registered")
		}
	})
}
