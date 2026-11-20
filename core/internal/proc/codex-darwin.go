//go:build darwin

package proc

import (
	"context"
	"strconv"
	"strings"
)

// CodexThreads lists live codex processes with the thread lock each holds. A failed or timed out `ps`
// is ErrUnknown. A failed `lsof` keeps the processes but marks each LockUnknown: without the lock listing a
// process that holds a thread cannot be told from one that has none yet.
func (s System) CodexThreads(ctx context.Context) ([]Thread, error) {
	ps, ok := run(ctx, orDefault(s.ps, psPath), []string{"-axo", "pid=,args="}, listTimeout)
	if !ok || ps.status != 0 {
		return nil, ErrUnknown
	}
	pids := CodexPids(ps.stdout)
	if len(pids) == 0 {
		return nil, nil
	}
	list := make([]string, len(pids))
	for i, p := range pids {
		list[i] = strconv.Itoa(p)
	}
	lsof, ran := run(ctx, orDefault(s.lsof, lsofPath), []string{"-nP", "-Fpn", "-p", strings.Join(list, ",")}, listTimeout)
	if !ran || !LsofUsable(lsof.status, lsof.stdout) {
		threads := make([]Thread, len(pids))
		for i, p := range pids {
			threads[i] = Thread{Pid: p, LockUnknown: true}
		}
		return threads, nil
	}
	return MergeThreads(pids, LockFds(lsof.stdout)), nil
}
