// Package identity holds the product's names, one constant each (SV12).
package identity

const (
	// Name is the binary and product name.
	Name = "spacevibe"
	// EnvPrefix starts every environment variable the core reads.
	EnvPrefix = "SPACEVIBE_"
	// DataDir is the data folder under the home directory.
	DataDir = ".spacevibe"
)

// Version is set at build time: -ldflags "-X spacevibe.dev/core/internal/identity.Version=1.2.3".
var Version = "dev"
