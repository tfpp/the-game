#!/usr/bin/env python3
"""Hotel teleport, range validation and late-joining observer over real WebSockets."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get('GODOT', 'godot')
SCENE = 'res://tests/features/hotel_annex/probe.tscn'


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='hotel-network-') as directory:
        logs = Path(directory)

        def start(name, args):
            handle = (logs / f'{name}.log').open('w')
            handles.append(handle)
            processes[name] = subprocess.Popen(
                [GODOT, '--headless', '--path', str(GAME), SCENE, '--',
                 '--dev-insecure-auth', f'--hotel-role={name}', *args],
                stdout=handle, stderr=subprocess.STDOUT)

        def wait(name, marker, timeout=45):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                text = (logs / f'{name}.log').read_text()
                assert 'ERROR:' not in text, text
                if marker in text:
                    return
                assert processes[name].poll() is None, text
                time.sleep(.05)
            raise AssertionError(f'Timed out waiting for {name}: {marker}')

        try:
            start('server', ['--server', f'--port={port}'])
            time.sleep(.8)
            start('driver', [f'--connect=ws://127.0.0.1:{port}', '--name=HotelVisitor'])
            wait('driver', 'HOTEL_ENTERED')
            start('observer', [f'--connect=ws://127.0.0.1:{port}', '--name=HotelObserver'])
            wait('driver', 'REENTRY_PASSED')
            wait('driver', 'ATRIUM_ROUND_TRIP_PASSED')
            wait('observer', 'OBSERVER_UNCHANGED')
            wait('server', 'SERVER_UNLOADED')
            print('PASS: range rejection, preloaded collision, round trip, unload, re-entry, '
                  'late observer unaffected and dedicated server geometry unloaded.')
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
