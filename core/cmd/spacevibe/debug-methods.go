//go:build !contracttest

package main

import "spacevibe.dev/core/internal/rpc"

// registerDebugMethods adds nothing: the shipped binary has no debug methods.
func registerDebugMethods(*rpc.Registry) {}
