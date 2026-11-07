#!/usr/bin/env bash
# End-to-end collector/setup checks on the Go binary (`spacevibe statusline install|undo|capture`), only synthetic
# homes; requires Python 3 for the test driver. H6 (plan): a shell started through os/exec keeps the default SIGPIPE
# and Claude's process group.
set -euo pipefail
cd "$(dirname "$0")/.."
build="$(mktemp -d "${TMPDIR:-/tmp}/spacevibe-statusline-build.XXXXXX")"
trap 'rm -rf "${build}"' EXIT
scripts/build-core.sh "${build}/spacevibe" >&2
python3 - "${build}/spacevibe" <<'PY'
import json, os, pathlib, select, shlex, signal, subprocess, sys, tempfile, time

binary = pathlib.Path(sys.argv[1]).resolve()

def home_env(root, data='.spacevibe'):
    claude = root / '.claude'
    return {**os.environ, 'HOME': str(root), 'CLAUDE_CONFIG_DIR': str(claude),
            'CODEX_HOME': str(root / '.codex'), 'SPACEVIBE_HOME': str(root / data), 'SPACEVIBE_TEST': '1'}

def install(env):
    return subprocess.run([binary, 'statusline', 'install'], env=env, capture_output=True, text=True, check=True)

with tempfile.TemporaryDirectory(prefix="spacevibe-statusline ' ") as scratch:
    root = pathlib.Path(scratch).resolve()
    claude = root / '.claude'
    claude.mkdir()
    (claude / '.claude.json').write_text(json.dumps({'oauthAccount': {'accountUuid': 'synthetic'}}))
    env = home_env(root)
    collector = root / '.spacevibe/bin/spacevibe'
    # Quotes in both the original command and paths exercise shell argument preservation.
    original = "cat; printf 'original-statusline\\n' >&2; exit 7"
    settings = claude / 'settings.json'
    before = json.dumps({'statusLine': {'type': 'command', 'command': original, 'padding': 2}, 'other': 'keep'})
    settings.write_text(before)
    installed = install(env)
    undo = shlex.split(installed.stdout.splitlines()[-1])
    assert undo[:3] == [str(collector), 'statusline', 'undo'], undo
    assert os.access(collector, os.X_OK) and (collector.stat().st_mode & 0o777) == 0o700
    command = json.loads(settings.read_text())['statusLine']['command']
    assert command.count('statusline capture') == 1
    install(env)
    assert json.loads(settings.read_text())['statusLine']['command'] == command
    payload = json.dumps({'session_id': 'synthetic-session', 'secret': 'do-not-store', 'rate_limits': {
        'seven_day': {'used_percentage': 76, 'resets_at': int(time.time()) + 86400}}}).encode()
    result = subprocess.run(['/bin/sh', '-c', command], input=payload, env=env, capture_output=True, timeout=10)
    assert result.returncode == 7 and result.stdout == payload
    assert result.stderr == b'original-statusline\n', result.stderr
    snapshot = root / '.spacevibe/claude-limits/synthetic-session.json'
    saved = snapshot.read_bytes()
    assert json.loads(saved)['rate_limits']['seven_day']['used_percentage'] == 76
    assert b'do-not-store' not in saved
    last_error = root / '.spacevibe/claude-limits/last-error'
    assert not last_error.exists()
    huge = b'x' * ((1 << 20) + 1)
    result = subprocess.run(['/bin/sh', '-c', command], input=huge, env=env, capture_output=True, timeout=10)
    assert result.returncode == 7 and result.stdout == huge
    assert b'Quota capture failed' in result.stderr
    assert snapshot.read_bytes() == saved
    # G-fix.19: the failure is recorded as a fixed reason, and a good capture clears it.
    assert last_error.read_text() == 'input-too-large\n', last_error.read_text()
    result = subprocess.run(['/bin/sh', '-c', command], input=payload, env=env, capture_output=True, timeout=10)
    assert result.returncode == 7 and not last_error.exists()
    # The delegate may stop reading stdin early; the collector must still finish without SIGPIPE.
    early = subprocess.run([collector, 'statusline', 'capture', str(root / '.spacevibe'),
                            str(claude), 'exit 0'], input=huge, env=env, capture_output=True, timeout=10)
    assert early.returncode == 0
    # Cancelling a status-line invocation must also cancel the original command, not orphan it in another group.
    pending = subprocess.Popen([collector, 'statusline', 'capture', str(root / '.spacevibe'),
                                str(claude), 'echo $$; sleep 20'], env=env, stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    try:
        assert select.select([pending.stdout], [], [], 5)[0], 'Delegate did not report its PID'
        delegate_pid = int(os.read(pending.stdout.fileno(), 64))
        assert os.getpgid(delegate_pid) == pending.pid
        os.killpg(pending.pid, signal.SIGTERM)
        pending.wait(timeout=5)
        for attempt in range(30):
            status = subprocess.run(['ps', '-p', str(delegate_pid), '-o', 'stat='], capture_output=True, text=True).stdout.strip()
            if not status or status.startswith('Z'): break
            time.sleep(0.1)
        else: raise AssertionError('Delegate survived group cancellation')
    finally:
        try: os.killpg(pending.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        pending.wait(timeout=5)
    # H6: the original gets the default SIGPIPE, also when the collector itself was started with SIGPIPE ignored
    # (restore_signals=False keeps Python's own SIG_IGN). `yes` ends by the signal (141) when `head` closes the pipe.
    sigpipe = '(yes; echo "yes=$?" >&2) | head -c1 >/dev/null'
    for restore in (True, False):
        run = subprocess.run([collector, 'statusline', 'capture', str(root / '.spacevibe'), str(claude), sigpipe],
                             input=b'{}', env=env, capture_output=True, timeout=10, restore_signals=restore)
        assert run.returncode == 0 and b'yes=141' in run.stderr, (restore, run.returncode, run.stderr)
    subprocess.run(undo, env=env, capture_output=True, check=True)
    assert settings.read_text() == before
    # Undo must refuse a later settings edit rather than clobber it.
    installed = install(env)
    undo = shlex.split(installed.stdout.splitlines()[-1])
    changed = settings.read_text() + '\n'
    settings.write_text(changed)
    assert subprocess.run(undo, env=env, capture_output=True).returncode == 1
    assert settings.read_text() == changed

# G-fix.19: an old wrapper is replaced, never wrapped again, also when the data root moved.
with tempfile.TemporaryDirectory(prefix="spacevibe-statusline-unwrap ") as scratch:
    root = pathlib.Path(scratch).resolve()
    (root / '.claude').mkdir()
    settings = root / '.claude/settings.json'
    mine = "printf 'it'\"'\"'s mine'"
    q = lambda text: "'" + text.replace("'", "'\\''") + "'"  # the POSIX quoting both collectors write
    legacy = f"{q('/Users/x/.reins/bin/reins-statusline')} --capture {q('/Users/x/.reins')} {q('/Users/x/.claude')} {q(mine)}"
    for old in (legacy, f"{q('/old/data/bin/spacevibe')} statusline capture {q('/old/data')} {q('/old/claude')} {q(mine)}"):
        settings.write_text(json.dumps({'statusLine': {'type': 'command', 'command': old}}))
        for data in ('.spacevibe', '.moved'):
            install(home_env(root, data))
            command = json.loads(settings.read_text())['statusLine']['command']
            assert command.count('statusline capture') + command.count('--capture') == 1, command
            assert shlex.split(command)[0] == str(root / data / 'bin/spacevibe') and shlex.split(command)[-1] == mine, command
print('PASS: capture, exact streams/exit, size cap, last-error, early pipe close, group cancellation, default SIGPIPE (H6), idempotence, old-wrapper unwrap, Undo and conflict refusal')
PY
