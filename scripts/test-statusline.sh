#!/usr/bin/env bash
# End-to-end collector/setup checks, only synthetic homes; requires Python 3 for the test driver.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product ReinsStatusline
python3 - "$(swift build --show-bin-path)/ReinsStatusline" <<'PY'
import json, os, pathlib, select, shlex, signal, subprocess, sys, tempfile, time

binary = pathlib.Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="reins-statusline ' ") as scratch:
    root = pathlib.Path(scratch)
    claude = root / '.claude'
    claude.mkdir()
    (claude / '.claude.json').write_text(json.dumps({'oauthAccount': {'accountUuid': 'synthetic'}}))
    env = {**os.environ, 'HOME': str(root), 'CLAUDE_CONFIG_DIR': str(claude),
           'CODEX_HOME': str(root / '.codex'), 'SPACEVIBE_HOME': str(root / '.spacevibe'), 'SPACEVIBE_TEST': '1'}
    # Quotes in both the original command and paths exercise shell argument preservation.
    original = "cat; printf 'original-statusline\\n' >&2; exit 7"
    settings = claude / 'settings.json'
    before = json.dumps({'statusLine': {'type': 'command', 'command': original, 'padding': 2}, 'other': 'keep'})
    settings.write_text(before)
    installed = subprocess.run([binary, '--install'], env=env, capture_output=True, text=True, check=True)
    undo = shlex.split(installed.stdout.splitlines()[-1])
    command = json.loads(settings.read_text())['statusLine']['command']
    subprocess.run([binary, '--install'], env=env, capture_output=True, check=True)
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
    huge = b'x' * ((1 << 20) + 1)
    result = subprocess.run(['/bin/sh', '-c', command], input=huge, env=env, capture_output=True, timeout=10)
    assert result.returncode == 7 and result.stdout == huge
    assert b'Quota capture failed' in result.stderr
    assert snapshot.read_bytes() == saved
    # The delegate may stop reading stdin early; the collector must still finish without SIGPIPE.
    early = subprocess.run([root / '.spacevibe/bin/reins-statusline', '--capture', str(root / '.spacevibe'),
                            str(claude), 'exit 0'], input=huge, env=env, capture_output=True, timeout=10)
    assert early.returncode == 0
    # Cancelling a status-line invocation must also cancel the original command, not orphan it in another group.
    pending = subprocess.Popen([root / '.spacevibe/bin/reins-statusline', '--capture', str(root / '.spacevibe'),
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
    subprocess.run(undo, env=env, capture_output=True, check=True)
    assert settings.read_text() == before
    # Undo must refuse a later settings edit rather than clobber it.
    installed = subprocess.run([binary, '--install'], env=env, capture_output=True, text=True, check=True)
    undo = shlex.split(installed.stdout.splitlines()[-1])
    changed = settings.read_text() + '\n'
    settings.write_text(changed)
    assert subprocess.run(undo, env=env, capture_output=True).returncode == 1
    assert settings.read_text() == changed
print('PASS: capture, exact streams/exit, size cap, early pipe close, group cancellation, idempotence, Undo and conflict refusal')
PY
