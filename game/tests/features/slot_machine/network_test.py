#!/usr/bin/env python3
"""Real server + two clients, with the observer joining during the first spin."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/features/slot_machine/network_probe.tscn"


def run():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    processes = []
    files = []
    with tempfile.TemporaryDirectory(prefix="slot-network-") as directory:
        logs = Path(directory)

        def start(name, arguments):
            handle = (logs / f"{name}.log").open("w")
            files.append(handle)
            processes.append(subprocess.Popen(
                [GODOT, "--headless", "--path", str(GAME), SCENE, "--", *arguments],
                stdout=handle, stderr=subprocess.STDOUT))

        def wait_for(name, marker, timeout=25):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if marker in (logs / f"{name}.log").read_text():
                    return
                assert all(p.poll() is None for p in processes), "A probe exited early"
                time.sleep(0.05)
            raise AssertionError(f"Timed out waiting for {name}: {marker}")

        try:
            start("server", ["--server", f"--port={port}", "--dev-insecure-auth"])
            time.sleep(0.8)
            start("driver", [f"--connect=ws://127.0.0.1:{port}", "--dev-insecure-auth",
                             "--name=SlotDriver", "--slot-role=driver"])
            wait_for("driver", "REQUEST 1")
            time.sleep(0.3)
            start("observer", [f"--connect=ws://127.0.0.1:{port}", "--dev-insecure-auth",
                               "--name=SlotObserver", "--slot-role=observer"])
            wait_for("driver", "DRIVER_DONE")
            time.sleep(0.4)
            results = {}
            for name in ("server", "driver", "observer"):
                text = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in text, text
                audio = [int(line.removeprefix("SLOT_AUDIO "))
                         for line in text.splitlines() if line.startswith("SLOT_AUDIO ")]
                assert audio == [1, 2, 3, 4, 5], (name, audio)
                states = [json.loads(line.removeprefix("SLOT_STATE "))
                          for line in text.splitlines() if line.startswith("SLOT_STATE ")]
                results[name] = [s for s in states if s["spin"] > 0 and not s["spinning"]]
                assert len(results[name]) == 5, (name, states)
                assert sum(s["won"] for s in results[name]) == 4, (name, states)
                assert all(s["operator"] == "SlotDriver" for s in results[name]), states
                for spin in range(1, 6):
                    phases = [s["stopped"] for s in states if s["spin"] == spin]
                    assert phases == [0, 1, 2, 3], (name, spin, phases)
            assert results["server"] == results["driver"] == results["observer"]
            assert "RANGE_REJECTED" in (logs / "driver.log").read_text()
            assert "COMPETING_REQUEST" in (logs / "observer.log").read_text()
            print("Slot network test passed: five identical results, four wins, ordered reels, "
                  "late join, range rejection, competing requests.")
        except BaseException:
            for log in logs.glob("*.log"):
                print(f"\n{log.name}:\n{log.read_text()}")
            raise
        finally:
            for process in processes:
                if process.poll() is None:
                    process.terminate()
            for process in processes:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            for handle in files:
                handle.close()


if __name__ == "__main__":
    run()
