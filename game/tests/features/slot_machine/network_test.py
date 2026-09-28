#!/usr/bin/env python3
"""Real server + two clients, with the observer joining during the first spin."""
import base64
import hashlib
import hmac
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import time
import urllib.request
import uuid

GAME = Path(__file__).resolve().parents[3]
GODOT = os.environ.get("GODOT", "godot")
SCENE = "res://tests/features/slot_machine/network_probe.tscn"


def run():
    persistent = os.environ.get("SLOT_TEST_DATABASE") == "1"
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
            server_auth = ["--dev-insecure-auth"]
            driver_auth = ["--dev-insecure-auth", "--name=SlotDriver"]
            observer_auth = ["--dev-insecure-auth", "--name=SlotObserver"]
            if persistent:
                key = uuid.uuid4().hex.encode()
                key_path = logs / "ticket.key"
                key_path.write_bytes(key)
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", 0))
                    api_port = sock.getsockname()[1]
                api_url = f"http://127.0.0.1:{api_port}/api"
                database = logs / "api.db"
                executable = logs / "api"
                subprocess.run(["go", "build", "-o", str(executable), "./cmd/api"],
                               cwd=GAME.parent / "api", check=True)
                handle = (logs / "api.log").open("w")
                files.append(handle)
                env = dict(os.environ, API_DB=str(database),
                           API_ADDR=f"127.0.0.1:{api_port}", API_TICKET_KEY_FILE=str(key_path))
                processes.append(subprocess.Popen([str(executable)], env=env,
                                                 stdout=handle, stderr=subprocess.STDOUT))
                for attempt in range(50):
                    try:
                        with urllib.request.urlopen(api_url + "/health", timeout=1):
                            break
                    except OSError:
                        time.sleep(0.1)
                with sqlite3.connect(database) as db:
                    for account_id, name in [(1, "SlotDriver"), (2, "SlotObserver")]:
                        db.execute("INSERT INTO accounts (id, display_name, created_at, updated_at) "
                                   "VALUES (?, ?, ?, ?)", (account_id, name, int(time.time()), int(time.time())))

                def ticket(account_id, name):
                    claims = {"aid": account_id, "name": name, "exp": int(time.time())+60,
                              "nonce": uuid.uuid4().hex}
                    message = b"v1." + base64.b64encode(json.dumps(claims).encode())
                    signature = hmac.new(key, message, hashlib.sha256).digest()
                    return (message + b"." + base64.b64encode(signature)).decode()

                server_auth = [f"--ticket-key-file={key_path}", f"--api={api_url}"]
                driver_auth = ["--ticket=" + ticket(1, "SlotDriver")]
                observer_auth = ["--ticket=" + ticket(2, "SlotObserver")]
            start("server", ["--server", f"--port={port}", *server_auth])
            time.sleep(0.8)
            start("driver", [f"--connect=ws://127.0.0.1:{port}", *driver_auth, "--slot-role=driver"])
            wait_for("driver", "REQUEST 1")
            time.sleep(0.3)
            start("observer", [f"--connect=ws://127.0.0.1:{port}", *observer_auth, "--slot-role=observer"])
            wait_for("driver", "DRIVER_DONE")
            time.sleep(0.4)
            results = {}
            wallets = {}
            for name in ("server", "driver", "observer"):
                text = (logs / f"{name}.log").read_text()
                assert "ERROR:" not in text, text
                money = [json.loads(line.removeprefix("SLOT_MONEY "))
                         for line in text.splitlines() if line.startswith("SLOT_MONEY ")]
                wallets[name] = money[-1]
                audio = [int(line.removeprefix("SLOT_AUDIO "))
                         for line in text.splitlines() if line.startswith("SLOT_AUDIO ")]
                assert audio == [1, 2, 3, 4, 5], (name, audio)
                states = [json.loads(line.removeprefix("SLOT_STATE "))
                          for line in text.splitlines() if line.startswith("SLOT_STATE ")]
                results[name] = [s for s in states if s["spin"] > 0 and not s["spinning"]]
                assert len(results[name]) == 5, (name, states)
                prizes = [3000, 2000, 1000, 1500, 2500]
                for state in results[name]:
                    a, b, c = state["reels"]
                    assert state["payout"] == (prizes[a] if a == b == c else 0)
                    assert state["won"] == (state["payout"] > 0)
                assert all(s["operator"] == "SlotDriver" for s in results[name]), states
                for spin in range(1, 6):
                    phases = [s["stopped"] for s in states if s["spin"] == spin]
                    assert phases == [0, 1, 2, 3], (name, spin, phases)
            assert results["server"] == results["driver"] == results["observer"]
            assert wallets["server"] == wallets["driver"] == wallets["observer"], wallets
            expected = 1500 + sum(s["payout"] for s in results["server"])
            assert sorted(wallets["server"].values()) == sorted([expected, 2000]), wallets
            assert "RANGE_REJECTED" in (logs / "driver.log").read_text()
            assert "COMPETING_REQUEST" in (logs / "observer.log").read_text()
            if persistent:
                with sqlite3.connect(database) as db:
                    assert db.execute("SELECT money FROM accounts WHERE id=1").fetchone()[0] == expected
                    assert db.execute("SELECT count(*) FROM slot_spins").fetchone()[0] == 5
                # Wait through a real minute: both connected accounts must receive
                # exactly $5, and every peer must see the updated balances.
                deadline = time.monotonic() + 65
                while time.monotonic() < deadline:
                    with sqlite3.connect(database) as db:
                        balances = dict(db.execute("SELECT id, money FROM accounts"))
                    if balances == {1: expected + 500, 2: 2500}:
                        break
                    time.sleep(0.1)
                assert balances == {1: expected + 500, 2: 2500}, balances
                time.sleep(0.5)
                for name in ("server", "driver", "observer"):
                    text = (logs / f"{name}.log").read_text()
                    assert "ERROR:" not in text, text
                    money = [json.loads(line.removeprefix("SLOT_MONEY "))
                             for line in text.splitlines() if line.startswith("SLOT_MONEY ")][-1]
                    assert sorted(money.values()) == sorted([expected+500, 2500]), (name, money)
                print("Database integration passed: authenticated spins, stored balances, $5 income, replication.")
            print("Slot network test passed: five identical paid results, ordered reels, "
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
