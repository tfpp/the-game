#!/usr/bin/env python3
"""Apartment travel and reservation replication with a late-joining WebSocket client."""
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
SCENE = "res://tests/features/apartments/probe.tscn"


def run():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    processes, handles = [], []
    with tempfile.TemporaryDirectory(prefix="apartments-") as directory:
        logs = Path(directory)

        def start(name, args):
            handle = (logs / f"{name}.log").open("w")
            handles.append(handle)
            processes.append(subprocess.Popen(
                ["godot", "--headless", "--path", str(GAME), SCENE, "--",
                 "--dev-insecure-auth", *args], stdout=handle, stderr=subprocess.STDOUT))

        def wait(name, marker):
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                if marker in (logs / f"{name}.log").read_text():
                    return
                assert all(p.poll() is None for p in processes), "Probe exited early"
                time.sleep(0.1)
            raise AssertionError(f"Timeout: {name} {marker}")

        try:
            start("server", ["--server", f"--port={port}"])
            time.sleep(1)
            start("driver", [f"--connect=ws://127.0.0.1:{port}",
                             "--name=Resident", "--apartment-role=driver"])
            wait("driver", "CLAIMED")
            start("observer", [f"--connect=ws://127.0.0.1:{port}",
                               "--name=Visitor", "--apartment-role=observer"])
            wait("observer", "LATE_OK")
            wait("driver", "APARTMENT_DONE")
            wait("observer", "APARTMENT_DONE")
            for name in ("server", "driver", "observer"):
                output = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in output, output
            print("PASS: apartment server, resident and late observer")
        except Exception:
            for path in logs.glob("*.log"):
                print(path.name, path.read_text()[-12000:])
            raise
        finally:
            for process in processes:
                process.terminate()
            for process in processes:
                process.wait(timeout=10)
            for handle in handles:
                handle.close()


if __name__ == "__main__":
    run()
