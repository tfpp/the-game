#!/usr/bin/env python3
"""One authoritative WASM interpreter and two independently emulated clients."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get('GODOT', 'godot')
SCENE = 'res://tests/features/scumm_arcade/network_probe.tscn'


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='scumm-network-') as directory:
        logs = Path(directory)

        def start(name, args):
            handle = (logs / f'{name}.log').open('w')
            handles.append(handle)
            processes[name] = subprocess.Popen(
                [GODOT, '--headless', '--path', str(GAME), SCENE, '--',
                 '--scumm-runtime', '--scumm-no-save', '--dev-insecure-auth', f'--arcade-role={name}', *args],
                stdout=handle, stderr=subprocess.STDOUT)

        def wait(name, marker, timeout=45):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                text = (logs / f'{name}.log').read_text()
                assert 'ERROR:' not in text and 'ARCADE_ERROR' not in text, text
                if marker in text:
                    return
                assert processes[name].poll() is None, text
                time.sleep(.05)
            raise AssertionError(f'Timed out waiting for {name}: {marker}')

        try:
            start('server', ['--server', f'--port={port}'])
            time.sleep(.8)
            start('driver', [f'--connect=ws://127.0.0.1:{port}', '--name=ArcadeDriver'])
            wait('driver', 'DRIVER_CONTROLS')
            # The observer must replay the already-running demo, including inputs.
            time.sleep(2)
            start('observer', [f'--connect=ws://127.0.0.1:{port}', '--name=ArcadeObserver'])
            wait('observer', 'COMPETING_REJECTED')
            wait('driver', 'DRIVER_DONE')
            wait('observer', 'CHECK 750 ')
            wait('server', 'CHECK 750 ')
            checks = {}
            for name in processes:
                text = (logs / f'{name}.log').read_text()
                assert 'ERROR:' not in text and 'ARCADE_ERROR' not in text, text
                checks[name] = {int(line.split()[1]): int(line.split()[2])
                                for line in text.splitlines() if line.startswith('CHECK ')}
            for tick in (250, 500, 750):
                assert len({checks[name][tick] for name in checks}) == 1, checks
            for game in ('monkey', 'samnmax', 'atlantis', 'pass', 'tentacle'):
                game_checks = []
                for name in processes:
                    text = (logs / f'{name}.log').read_text()
                    game_checks.append({int(line.split()[2]): int(line.split()[3])
                        for line in text.splitlines() if line.startswith(f'FLOOR_CHECK {game} ')})
                for tick in (250, 500):
                    assert len({checks[tick] for checks in game_checks}) == 1, (game, game_checks)
            processes['driver'].terminate()
            processes['driver'].wait(timeout=5)
            wait('observer', 'HANDOFF_DONE')
            print('PASS: server + 2 clients agree at ticks 250/500/750; late replay, '
                  'all 5 cabinets agree; range rejection, competing input rejection, disconnect handoff.')
        except BaseException:
            for log in logs.glob('*.log'):
                print(f'\n{log.name}:\n{log.read_text()}')
            raise
        finally:
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


if __name__ == '__main__':
    run()
