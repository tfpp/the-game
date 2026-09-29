#!/usr/bin/env python3
"""Real server, operator and late joining competing client."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]


def run():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    processes, handles = {}, []
    with tempfile.TemporaryDirectory(prefix='computer-network-') as directory:
        logs = Path(directory)

        def start(name, args):
            handle = (logs / f'{name}.log').open('w')
            handles.append(handle)
            processes[name] = subprocess.Popen(
                [os.environ.get('GODOT', 'godot'), '--headless', '--path', str(GAME),
                 'res://tests/features/computers/network_probe.tscn', '--',
                 '--scumm-no-save', '--dev-insecure-auth', f'--computer-role={name}', *args],
                stdout=handle, stderr=subprocess.STDOUT)

        def wait(name, marker):
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                for log in logs.glob('*.log'):
                    assert 'ERROR:' not in log.read_text(), log.read_text()
                text = (logs / f'{name}.log').read_text()
                if marker in text:
                    return
                assert processes[name].poll() is None, text
                time.sleep(.05)
            raise AssertionError(f'Timed out waiting for {name}: {marker}')

        try:
            start('server', ['--server', f'--port={port}'])
            time.sleep(.8)
            start('driver', [f'--connect=ws://127.0.0.1:{port}', '--name=ComputerDriver'])
            wait('driver', 'DRIVER_SCORED')
            start('observer', [f'--connect=ws://127.0.0.1:{port}', '--name=ComputerObserver'])
            wait('observer', 'LATE_JOIN_AND_COMPETING_REJECTED')
            processes['driver'].terminate()
            processes['driver'].wait(timeout=5)
            wait('observer', 'HANDOFF_DONE')
            print('PASS: live late-join score, competing RPC rejection, disconnect handoff and new round.')
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
