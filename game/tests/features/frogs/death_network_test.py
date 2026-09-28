#!/usr/bin/env python3
"""Real WebSocket peers: frog death, client authority, late join and respawn."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/features/frogs/death_network_probe.tscn"


def run():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    processes, handles = [], []
    with tempfile.TemporaryDirectory(prefix="frog-network-") as directory:
        logs = Path(directory)

        def start(name, args):
            handle = (logs / f"{name}.log").open("w")
            handles.append(handle)
            processes.append(subprocess.Popen(
                [GODOT, "--headless", "--path", str(GAME), SCENE, "--", *args],
                stdout=handle, stderr=subprocess.STDOUT))

        def wait_for(name, marker):
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                if marker in (logs / f"{name}.log").read_text():
                    return
                assert all(p.poll() is None for p in processes), "A probe exited early"
                time.sleep(0.05)
            raise AssertionError(f"Timed out waiting for {name}: {marker}")

        try:
            start("server", ["--server", f"--port={port}", "--dev-insecure-auth"])
            time.sleep(1)
            common = [f"--connect=ws://127.0.0.1:{port}", "--dev-insecure-auth"]
            start("driver", common + ["--name=FrogDriver", "--frog-role=driver"])
            wait_for("driver", "FROG_CLIENT_DEAD")
            start("observer", common + ["--name=FrogObserver", "--frog-role=late"])
            wait_for("observer", "FROG_CLIENT_DEAD")
            wait_for("driver", "FROG_CLIENT_RESPAWNED")
            wait_for("observer", "FROG_CLIENT_RESPAWNED")
            for name in ("server", "driver", "observer"):
                content = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in content, f"{name}: {content}"
            print("Frog multiplayer passed: authority, explosion, dead late join and respawn")
        except Exception:
            for log in logs.glob("*.log"):
                print(f"--- {log.name} ---\n{log.read_text()}")
            raise
        finally:
            for process in processes:
                process.terminate()
            for process in processes:
                process.wait(timeout=5)
            for handle in handles:
                handle.close()


if __name__ == "__main__":
    run()
