"""Run from the repository root: python3 game/tests/features/kaaba/run_network.py."""
import pathlib
import socket
import subprocess
import tempfile
import time

logs = pathlib.Path(tempfile.mkdtemp(prefix="kaaba-network-"))
processes = []
streams = []
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]


def start(role, options):
    stream = (logs / (role + ".log")).open("w")
    streams.append(stream)
    processes.append(subprocess.Popen([
        "godot", "--headless", "--path", "game",
        "res://tests/features/slot_machine/network_probe.tscn", "--",
        "--dev-insecure-auth", "--slot-role=" + role, "--name=" + role,
        *options,
    ], stdout=stream, stderr=subprocess.STDOUT))


def read(role):
    return (logs / (role + ".log")).read_text()


def wait_for(role, marker, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if marker in read(role):
            return
        time.sleep(0.2)
    raise AssertionError(f"{role} timed out waiting for {marker}; logs: {logs}")


try:
    start("server", ["--server", f"--port={port}"])
    wait_for("server", "Server listening", 30)
    connection = [f"--connect=ws://127.0.0.1:{port}"]
    start("observer", connection)
    start("driver", connection)
    wait_for("driver", "BLESSING_RECEIVED", 45)
    start("late", connection)
    wait_for("driver", "DRIVER_DONE", 60)
    for role in ("driver", "observer"):
        assert "BLESSING_EVENT completed" in read(role), role
        assert "BLESSING_EVENT gamble" in read(role), role
    assert ":1}" in read("late"), "late joiner missed replicated blessing"
    assert "BLESSING_EVENT completed" not in read("late"), "replayed old VFX"
    assert "BLESSING_EVENT gamble" in read("late"), "late joiner missed live VFX"
    for role in ("server", "driver", "observer", "late"):
        assert "SCRIPT ERROR" not in read(role), role
    print(f"PASS: prayer, blessed spins, observer events, late join; logs: {logs}")
finally:
    for process in processes:
        process.terminate()
    for process in processes:
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
    for stream in streams:
        stream.close()
