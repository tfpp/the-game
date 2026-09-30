"""Run from the repository root: python3 game/tests/features/kaaba/network_test.py."""
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
processes = {}
logs = {}
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]


def spawn(role):
    path = directory / (role + ".log")
    logs[role] = path
    with path.open("w") as output:
        processes[role] = subprocess.Popen(
            [os.environ.get("GODOT", "godot"), "--headless", "--path", str(GAME),
             "res://tests/features/kaaba/network_probe.tscn", "--",
             "--prayer-role=" + role, "--prayer-port=" + str(port)],
            stdout=output, stderr=subprocess.STDOUT,
        )


def wait(role, marker):
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        for name, path in logs.items():
            text = path.read_text()
            if "ERROR:" in text or "SCRIPT ERROR" in text:
                raise AssertionError(name + ": " + text)
        if marker in logs[role].read_text():
            return
        if processes[role].poll() is not None:
            raise AssertionError(role + " exited before " + marker)
        time.sleep(0.1)
    raise AssertionError(role + " timed out waiting for " + marker)


with tempfile.TemporaryDirectory(prefix="kaaba-network-") as temp:
    directory = Path(temp)
    try:
        spawn("server")
        wait("server", "PROBE_READY")
        spawn("observer")
        wait("observer", "PROBE_READY")
        time.sleep(0.5)
        spawn("driver")
        wait("driver", "FORGED_REJECTED")
        wait("observer", "PRAYING_REPLICATED")
        spawn("late")
        wait("late", "PRAYING_REPLICATED")
        for role in ("driver", "observer", "late"):
            wait(role, "BLESSING_REPLICATED")
        spawn("late_done")
        wait("late_done", "BLESSING_REPLICATED")
        processes["driver"].terminate()
        processes["driver"].wait(timeout=5)
        wait("server", "DISCONNECT_CLEAN")
        for role in ("observer", "late", "late_done"):
            wait(role, "CLEANUP_REPLICATED")
        print("Kaaba networking: PASS (sender validation, broadcast, late join, cleanup)")
    except Exception:
        for role, path in logs.items():
            print(role, path.read_text())
        raise
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
