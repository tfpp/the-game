#!/usr/bin/env python3
"""Real authenticated server + driver + late observer appearance regression."""
import argparse
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--emotes", action="store_true")
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[3]
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="avatar-network-") as directory:
        root = Path(directory)
        stop = root / "stop"
        processes = {}
        logs = {}
        files = []

        def spawn(role):
            log = root / f"{role}.log"
            stream = log.open("w")
            files.append(stream)
            command = [args.godot, "--headless", "--path", str(game),
                       "res://tests/features/player_models/network_probe.tscn", "--",
                       "--dev-insecure-auth", f"--avatar-role={role}",
                       f"--probe-stop={stop}", f"--name={role}"]
            command += (["--server", f"--port={port}"] if role == "server" else
                        [f"--connect=ws://127.0.0.1:{port}"])
            if args.emotes:
                command.append("--emote-probe")
            processes[role] = subprocess.Popen(command, stdout=stream, stderr=stream)
            logs[role] = log

        def wait(check):
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                for role, process in processes.items():
                    text = logs[role].read_text()
                    if process.poll() is not None or "ERROR:" in text:
                        raise RuntimeError(f"{role} failed:\n{text}")
                if check():
                    return
                time.sleep(0.05)
            raise RuntimeError("Timed out waiting for appearance replication")

        try:
            spawn("server")
            wait(lambda: "Server listening" in logs["server"].read_text())
            spawn("driver")
            wait(lambda: "AVATAR_DRIVER_PASS" in logs["driver"].read_text()
                 and "AVATAR_OBSERVED" in logs["server"].read_text())
            spawn("late")
            wait(lambda: "AVATAR_OBSERVED" in logs["late"].read_text())
            if args.emotes:
                wait(lambda: all("EMOTE_OBSERVED" in log.read_text() for log in logs.values()))
                wait(lambda: all("EMOTE_FINISHED" in log.read_text() for log in logs.values()))
            Path(str(stop) + ".pause").touch()
            wait(lambda: all("AVATAR_PAUSED" in log.read_text() for log in logs.values()))
            stop.touch()
            for process in processes.values():
                process.wait(timeout=10)
            for role, log in logs.items():
                if processes[role].returncode or "ERROR:" in log.read_text():
                    raise RuntimeError(f"{role} failed:\n{log.read_text()}")
            print("PASS: appearance identity, validation, replication and late join")
            if args.emotes:
                print("PASS: emote identity, cooldown, synchronized late-join phase and expiry")
        except Exception:
            for role, log in logs.items():
                print(f"{role}:\n{log.read_text()}")
            raise
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
                    process.wait()
            for stream in files:
                stream.close()


if __name__ == "__main__":
    main()
