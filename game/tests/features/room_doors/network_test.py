#!/usr/bin/env python3
"""Door/key authority and replication with two clients plus a late joiner."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get('GODOT', 'godot')
SCENE = 'res://tests/features/room_doors/network_probe.tscn'


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='doors-network-') as directory:
        logs = Path(directory)
        stop = logs / 'stop'

        def start(name, args):
            handle = (logs / f'{name}.log').open('w')
            handles.append(handle)
            processes[name] = subprocess.Popen(
                [GODOT, '--headless', '--path', str(GAME), SCENE, '--',
                 '--dev-insecure-auth', f'--door-role={name}', f'--probe-stop={stop}',
                 f'--name={name}', *args], stdout=handle, stderr=subprocess.STDOUT)

        def wait(name, marker):
            deadline = time.monotonic() + 45
            while time.monotonic() < deadline:
                for log in logs.glob('*.log'):
                    text = log.read_text()
                    assert 'ERROR:' not in text, text
                text = (logs / f'{name}.log').read_text()
                if marker in text:
                    return
                assert processes[name].poll() is None, text
                time.sleep(.05)
            raise AssertionError(f'Timed out: {name} / {marker}')

        try:
            start('server', ['--server', f'--port={port}'])
            wait('server', 'DOORS_SERVER_READY')
            for name in ['observer', 'driver']:
                start(name, [f'--connect=ws://127.0.0.1:{port}'])
            wait('driver', 'DOORS_DRIVER_PASSED')
            wait('observer', 'DOORS_OBSERVER_PASSED')
            start('late', [f'--connect=ws://127.0.0.1:{port}'])
            wait('late', 'DOORS_LATE_JOIN_PASSED')
            for name in processes:
                wait(name, 'ENTITY_DESPAWN_OBSERVED')
            Path(str(stop) + '.pause').touch()
            for name in processes:
                wait(name, 'DOORS_QUIESCED')
            stop.touch()
            for process in processes.values():
                assert process.wait(timeout=10) == 0
            for log in logs.glob('*.log'):
                assert 'ERROR:' not in log.read_text(), log.read_text()
            print('PASS: registered entity actions, validation, sender identity, server '
                  'spawn/despawn, late join snapshots, shared doors, three-hotel sewer access, ladder owner movement, audio, key ring and streaming.')
        except BaseException:
            for log in logs.glob('*.log'):
                print(f'\n{log.name}:\n{log.read_text()}')
            raise
        finally:
            stop.touch()
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
