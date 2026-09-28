#!/usr/bin/env python3
"""Real server and two clients: shared craps results and a mid-roll join."""
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/features/craps/network_probe.tscn"

def run():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    processes = []
    files = []
    with tempfile.TemporaryDirectory(prefix="craps-network-") as directory:
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
            server_auth = ["--dev-insecure-auth"]
            driver_auth = ["--dev-insecure-auth", "--name=CrapsDriver"]
            observer_auth = ["--dev-insecure-auth", "--name=CrapsObserver"]
            start("server", ["--server", f"--port={port}", *server_auth])
            time.sleep(0.8)
            start("driver", [f"--connect=ws://127.0.0.1:{port}", *driver_auth, "--craps-role=driver"])
            wait_for("driver", "REQUEST 1")
            time.sleep(0.3)
            start("observer", [f"--connect=ws://127.0.0.1:{port}", *observer_auth, "--craps-role=observer"])
            wait_for("driver", "DRIVER_DONE")
            time.sleep(0.4)
            results = {}
            for name in ("server", "driver", "observer"):
                text = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in text, text
                states = [json.loads(line.removeprefix("CRAPS_STATE "))
                          for line in text.splitlines() if line.startswith("CRAPS_STATE ")]
                results[name] = [s for s in states if s["roll"] > 0 and not s["rolling"]]
                assert [s["roll"] for s in results[name]] == [1, 2, 3, 4, 5], states
                assert all(s["operator"] == "CrapsDriver" for s in results[name]), states
                assert any(s["roll"] == 1 and s["rolling"] for s in states), "Missing mid-roll join"
            assert results["server"] == results["driver"] == results["observer"]
            point = 0
            for state in results["server"]:
                a, b = state["dice"]
                assert 1 <= a <= 6 and 1 <= b <= 6
                total = a + b
                if point == 0:
                    if total in (7, 11):
                        outcome = "win"
                    elif total in (2, 3, 12):
                        outcome = "lose"
                    else:
                        point, outcome = total, "point"
                elif total == point or total == 7:
                    outcome = "win" if total == point else "lose"
                    point = 0
                else:
                    outcome = "continue"
                assert state["point"] == point and state["outcome"] == outcome, state
            assert "RANGE_REJECTED" in (logs / "driver.log").read_text()
            assert "COMPETING_REQUEST" in (logs / "observer.log").read_text()
            print("Craps network test passed: five matching results, mid-roll join, "
                  "range rejection and duplicate/competing requests.")
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
