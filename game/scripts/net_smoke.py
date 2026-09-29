#!/usr/bin/env python3
"""Check real game peers, then reap every engine process on Windows and Unix."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[1]
GODOT = os.environ.get('GODOT', 'godot')
if os.name == 'nt' and GODOT.endswith('_console.exe'):
    engine = Path(GODOT.removesuffix('_console.exe') + '.exe')
    if engine.is_file():
        GODOT = str(engine)


def roster(text):
    lines = [line for line in text.splitlines() if line.startswith('ROSTER')]
    return lines[-1] if lines else ''


def ready(logs):
    for name in ['server', 'c1', 'c2']:
        last = roster(logs[name])
        peers = last.partition('players=')[2].split(',')
        if len([peer for peer in peers if peer]) != 2:
            return False
    return (
        all(f'authenticated as {name}' in logs['server'] for name in ['Alice', 'Bob'])
        and 'Connection failed: invalid or expired join ticket' in logs['intruder']
        and 'Connection failed: This game is version stale but the server runs dev'
        in logs['stale']
    )


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = int(os.environ.get('PORT', sock.getsockname()[1]))
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='game-net-smoke-') as directory:
        root = Path(directory)

        def start(name, args):
            handle = (root / f'{name}.log').open('w', encoding='utf-8')
            handles.append(handle)
            processes[name] = subprocess.Popen(
                [GODOT, '--headless', '--path', str(GAME), '--', *args],
                stdout=handle, stderr=subprocess.STDOUT)

        def logs():
            return {name: (root / f'{name}.log').read_text(encoding='utf-8', errors='replace')
                    for name in processes}

        def wait(predicate):
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                output = logs()
                for name, text in output.items():
                    assert 'ERROR:' not in text, f'{name}: {text}'
                    assert processes[name].poll() is None, f'{name} exited: {text}'
                if predicate(output):
                    return
                time.sleep(.05)
            raise AssertionError('Timed out waiting for multiplayer smoke checks')

        try:
            start('server', ['--server', f'--port={port}', '--dev-insecure-auth', '--debug-roster'])
            wait(lambda output: 'Server listening on port' in output['server'])
            url = f'ws://127.0.0.1:{port}'
            for peer, name in [('c1', 'Alice'), ('c2', 'Bob')]:
                start(peer, [f'--connect={url}', '--dev-insecure-auth', f'--name={name}', '--debug-roster'])
            start('intruder', [f'--connect={url}', '--ticket=v1.forged.ticket'])
            start('stale', [f'--connect={url}', '--dev-insecure-auth', '--build-version=stale'])
            started = time.monotonic()
            wait(lambda output: ready(output) and time.monotonic() - started >= 6)
            for name in ['server', 'c1', 'c2']:
                print(f'{name}: {roster(logs()[name])}')
        except BaseException:
            for name, text in logs().items():
                print(f'\n{name}:\n{text}')
            raise
        finally:
            # Own the engine directly instead of Git Bash's background wrappers
            # or the Windows console launcher's detached child process.
            for process in processes.values():
                if process.poll() is None:
                    process.terminate()
            for process in processes.values():
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for handle in handles:
                handle.close()
        for name, text in logs().items():
            assert 'ERROR:' not in text, f'{name}: {text}'
    print('multiplayer smoke passed')


if __name__ == '__main__':
    run()
