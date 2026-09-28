#!/usr/bin/env python3
"""Kill/restart a real server; a new client must reconstruct the saved WASM run."""
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
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='scumm-persistence-') as directory:
        root = Path(directory)
        save = root / 'progress.sav'
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]

        def start(name, role, server=False):
            handle = (root / f'{name}.log').open('w')
            handles.append(handle)
            args = ['--server', f'--port={port}'] if server else [
                f'--connect=ws://127.0.0.1:{port}', '--name=ReturningPlayer']
            processes[name] = subprocess.Popen([
                GODOT, '--headless', '--path', str(GAME), SCENE, '--',
                '--scumm-runtime', '--dev-insecure-auth', f'--arcade-role={role}',
                f'--scumm-save-path={save}', *args], stdout=handle, stderr=subprocess.STDOUT)

        def wait(name, marker, timeout=60):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                text = (root / f'{name}.log').read_text()
                assert 'ERROR:' not in text and 'ARCADE_ERROR' not in text, text
                if marker in text:
                    return text
                assert processes[name].poll() is None, text
                time.sleep(.05)
            raise AssertionError(f'{name} did not reach {marker}')

        def kill(name):
            processes[name].kill()
            processes[name].wait(timeout=5)

        try:
            start('original', 'server', True)
            wait('original', 'Server listening')
            start('driver', 'driver')
            wait('driver', 'DRIVER_DONE')
            original = wait('original', 'CHECK 750 ')
            baseline = next(line for line in original.splitlines() if line.startswith('CHECK 750 '))
            # Drop the controlling peer abruptly; the server must save and pause.
            kill('driver')
            time.sleep(2)
            assert save.exists(), 'Disconnect did not save progress'
            saved = save.read_bytes()
            time.sleep(5.5)
            assert save.read_bytes() == saved, 'Empty arcade continued advancing'
            kill('original')
            start('restarted', 'server', True)
            restored = wait('restarted', 'ARCADE_RESTORED ')
            tick = int(next(line.split()[1] for line in restored.splitlines()
                            if line.startswith('ARCADE_RESTORED ')))
            assert tick >= 750, tick
            start('returning', 'restored')
            client = wait('returning', 'RESTORED_PROGRESS')
            server = wait('restarted', 'CHECK 750 ')
            assert baseline in client and baseline in server, (baseline, client, server)
            for game in ('samnmax', 'atlantis', 'pass', 'tentacle'):
                assert Path(str(save) + '.' + game).exists(), game
                marker = f'FLOOR_CHECK {game} 500 '
                prior = next(line for line in original.splitlines() if line.startswith(marker))
                assert prior in wait('returning', marker) and prior in wait('restarted', marker), game
            print(f'PASS: saved tick {tick}; empty arcade paused; killed server restored; '
                  'new client and restored server reproduce the original checkpoint hash; '
                  'no stale controller.')
        except BaseException:
            for log in root.glob('*.log'):
                print(f'\n{log.name}:\n{log.read_text()}')
            raise
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                process.wait(timeout=5)
            for handle in handles:
                handle.close()


if __name__ == '__main__':
    run()
