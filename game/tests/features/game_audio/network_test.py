#!/usr/bin/env python3
"""Real peers verify shot audio events, cooldown, ownership and late joining."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/features/game_audio/network_probe.tscn"


def run():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    processes, handles = [], []
    with tempfile.TemporaryDirectory(prefix="audio-network-") as directory:
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
            start("driver", common + ["--name=InventoryDriver", "--audio-role=driver"])
            wait_for("driver", "AUDIO_DRIVER_READY")
            start("observer", common + ["--name=InventoryObserver", "--audio-role=observer"])
            wait_for("observer", "AUDIO_OBSERVER_READY")
            wait_for("driver", "AUDIO_DRIVER_DONE")
            wait_for("observer", "AUDIO_OBSERVER_DONE")
            for name in ("server", "driver", "observer"):
                content = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in content, f"{name}: {content}"
            print("Audio multiplayer passed: shooting, cooldown, ownership, late join, spatial origin")
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
