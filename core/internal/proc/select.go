package proc

import "spacevibe.dev/core/internal/config"

// New picks the adapter, with the gating of AppEnvironment.live: under SPACEVIBE_TEST=1 the process
// list is a fixture (the file at fixturePath, or empty when none is given), so test mode can never see
// a real process; otherwise it is the system adapter and fixturePath is ignored. A fixture file that
// cannot be read yields the empty fixture together with the error, as the Swift app records a startup
// problem and carries on. fixturePath is SPACEVIBE_PROC_FIXTURE, which the caller reads through
// internal/config.
func New(cfg config.Config, fixturePath string) (Adapter, error) {
	if !cfg.Test {
		return NewSystem(), nil
	}
	if fixturePath == "" {
		return NewFixture(nil, nil, nil, 0), nil
	}
	f, err := LoadFixture(fixturePath)
	if err != nil {
		return NewFixture(nil, nil, nil, 0), err
	}
	return f, nil
}
