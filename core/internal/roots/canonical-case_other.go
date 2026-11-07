//go:build !darwin

package roots

// canonicalCase is the identity off darwin: Linux volumes are case-sensitive, and the Windows
// spelling is not normalised (not a supported test host).
func canonicalCase(path string) string { return path }
