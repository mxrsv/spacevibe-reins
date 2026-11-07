package methods

import (
	"context"
	"errors"
	"fmt"

	"spacevibe.dev/core/internal/activity"
	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/limits"
	"spacevibe.dev/core/internal/mutate"
	"spacevibe.dev/core/internal/rpc"
)

var errUnavailable = coreerr.NewStatus("The core could not start.", coreerr.StatusInternalFailure)

// none is the params of a method that takes none: any member is refused.
type none struct{}

// typed decodes params strictly into P and calls fn. Failures that are not safe to forward are logged by type.
func typed[P, R any](s *Services, name string, fn func(context.Context, P) (R, error)) rpc.Handler {
	return func(ctx context.Context, call rpc.Call) (any, error) {
		var p P
		if err := rpc.DecodeParams(call.Params, &p); err != nil {
			return nil, err
		}
		res, err := fn(ctx, p)
		if err != nil {
			s.noteFailure(name, err)
			return nil, err
		}
		return res, nil
	}
}

// noteFailure logs the type of an error the shell will see as -32603. The text may quote a file.
func (s *Services) noteFailure(name string, err error) {
	var re *rpc.Error
	if _, ok := coreerr.As(err); ok || errors.As(err, &re) || errors.Is(err, context.Canceled) {
		return
	}
	fmt.Fprintf(s.log, "spacevibe: %s failed: %T\n", name, err)
}

func (s *Services) buildHandlers() map[string]rpc.Handler {
	return map[string]rpc.Handler{
		"inventory.read":          typed(s, "inventory.read", s.inventoryRead),
		"usage.scan":              s.usageScan,
		"loadout.rows":            typed(s, "loadout.rows", s.loadoutRows),
		"activity.read":           typed(s, "activity.read", func(ctx context.Context, _ none) (activity.Report, error) { return s.activity.Read(ctx) }),
		"activity.subscribe":      s.activitySubscribe,
		"activity.unsubscribe":    typed(s, "activity.unsubscribe", s.activityUnsubscribe),
		"activity.stop":           typed(s, "activity.stop", s.activityStop),
		"loadout.copyToOther":     typed(s, "loadout.copyToOther", s.mutate.CopyToOther),
		"loadout.removeItem":      typed(s, "loadout.removeItem", s.mutate.RemoveItem),
		"loadout.removeDeadHooks": typed(s, "loadout.removeDeadHooks", s.mutate.RemoveDeadHooks),
		"journal.undo":            typed(s, "journal.undo", s.mutate.Undo),
		"journal.history":         typed(s, "journal.history", func(ctx context.Context, _ none) (mutate.HistoryResult, error) { return s.mutate.History(ctx) }),
		"rules.snapshot":          typed(s, "rules.snapshot", s.rules.Snapshot),
		"rules.preview":           typed(s, "rules.preview", s.rules.Preview),
		"rules.setCapability":     typed(s, "rules.setCapability", s.rules.SetCapability),
		"rules.add":               typed(s, "rules.add", s.rules.Add),
		"rules.remove":            typed(s, "rules.remove", s.rules.Remove),
		"rules.changeVerdict":     typed(s, "rules.changeVerdict", s.rules.ChangeVerdict),
		"rules.check":             typed(s, "rules.check", s.rules.Check),
		"limits.read":             typed(s, "limits.read", s.limitsRead),
	}
}

func (s *Services) limitsRead(ctx context.Context, _ none) (limits.Result, error) {
	return limits.Read(ctx, s.cfg, s.roots, s.now())
}

// StopParams is the params of activity.stop: the session by CLI and id, never by pid (S-R4).
type StopParams struct {
	CLI activity.CLI `json:"cli"`
	ID  string       `json:"id"`
}

func (s *Services) activityStop(ctx context.Context, p StopParams) (activity.StopResult, error) {
	if p.CLI != activity.CLIClaude && p.CLI != activity.CLICodex {
		return activity.StopResult{}, coreerr.New("cli must be claude or codex.")
	}
	if p.ID == "" {
		return activity.StopResult{}, coreerr.New("A session id is required.")
	}
	return s.activity.Stop(ctx, p.CLI, p.ID)
}
