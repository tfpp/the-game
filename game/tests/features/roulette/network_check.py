#!/usr/bin/env python3
"""Real server + two seated bettors + late observer roulette regression.

Run: python3 game/tests/features/roulette/network_check.py [--godot=godot]
"""
import argparse
import json
import re
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="godot")
    args = parser.parse_args()
    game = Path(__file__).resolve().parents[3]
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        port = listener.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="roulette-network-") as directory:
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
                       "res://tests/features/roulette/network_probe.tscn", "--",
                       "--dev-insecure-auth", f"--roulette-role={role}",
                       f"--probe-stop={stop}", f"--name={role}"]
            command += (["--server", f"--port={port}"] if role == "server" else
                        [f"--connect=ws://127.0.0.1:{port}"])
            processes[role] = subprocess.Popen(command, stdout=stream, stderr=stream)
            logs[role] = log

        def text(role):
            return logs[role].read_text()

        def wait(check, seconds=40):
            deadline = time.monotonic() + seconds
            while time.monotonic() < deadline:
                for role, process in processes.items():
                    if process.poll() is not None or "ERROR:" in text(role):
                        raise RuntimeError(f"{role} failed:\n{text(role)}")
                if check():
                    return
                time.sleep(0.05)
            raise RuntimeError("Timed out waiting for roulette replication")

        try:
            spawn("server")
            wait(lambda: "Server listening" in text("server"))
            spawn("a")
            spawn("b")
            wait(lambda: all("ROULETTE_BETS_PLACED" in text(r) for r in ("a", "b")))
            spawn("late")
            wait(lambda: "ROULETTE_LATE_SAW" in text("late"))
            wait(lambda: all("ROULETTE_RESULT" in text(r) for r in processes))
            wait(lambda: all("ROULETTE_RELEASED" in text(r) for r in ("a", "b", "late")))
            results = {}
            for role in processes:
                line = re.search(r"ROULETTE_RESULT (.*)", text(role)).group(1)
                results[role] = line
            if len(set(results.values())) != 1:
                raise RuntimeError(f"peers disagree on the result: {results}")
            number = int(re.search(r"number=(\d+)", results["server"]).group(1))
            settled = json.loads(re.search(r"results=(\{.*?\}\}) ", results["server"]).group(1))
            for role in ("a", "b"):
                done = re.search(r"ROULETTE_DRIVER_DONE (.*)", text(role)).group(1).split()
                # 3 = DENIED: the forged-peer bet, the $50 chip and leaving mid-spin.
                if done.count("bet=3") != 2 or "leave=3" not in done:
                    raise RuntimeError(f"{role} requests were not refused: {done}")
            for result in settled.values():
                if result["wager"] != 600 or result["status"] not in ("won", "lost"):
                    raise RuntimeError(f"unexpected settlement {settled}")
            stop.touch()
            for process in processes.values():
                process.wait(timeout=10)
            for role in processes:
                if processes[role].returncode or "ERROR:" in text(role):
                    raise RuntimeError(f"{role} failed:\n{text(role)}")
            print(f"PASS: seats, bets, refusals, late join, spin on {number} and settlement")
        except Exception:
            for role in logs:
                print(f"{role}:\n{text(role)}")
            raise
        finally:
            for process in processes.values():
                if process.poll() is None:
                    process.kill()
            for stream in files:
                stream.close()


if __name__ == "__main__":
    main()
