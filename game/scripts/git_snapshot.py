#!/usr/bin/env python3
"""Fixed metadata queries only. Never accepts player input or reads file contents."""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
QUERIES = {
    "log": ["log", "-20", "--format=%h %s"],
    "show": ["show", "--format=%h %s", "--stat", "--no-ext-diff",
             "--no-textconv", "--no-renames", "HEAD", "--"],
    "status": ["status", "--short", "--untracked-files=no"],
    "branch": ["branch", "--show-current"],
    "rev-parse HEAD": ["rev-parse", "HEAD"],
    "ls-files": ["ls-files"],
}
LIMIT = 12000


def snapshot(root=ROOT):
    data = {}
    for name, args in QUERIES.items():
        result = subprocess.run(
            ["git", "--no-pager", "--no-optional-locks", "-c", "core.fsmonitor=false",
             "-c", "color.ui=false", "-C", str(root), *args],
            capture_output=True, text=True, check=True, timeout=10,
        )
        value = result.stdout.strip()
        if len(value) > LIMIT:
            value = value[:LIMIT] + "\n[Output truncated to 12000 characters.]"
        data[name] = value
    data["status"] = data["status"] or "No tracked changes at snapshot time."
    data["branch"] = data["branch"] or "(detached HEAD)"
    return data


if __name__ == "__main__":
    try:
        payload = json.dumps(snapshot(), ensure_ascii=True)
    except (OSError, subprocess.SubprocessError):
        print("Repository snapshot unavailable.", file=sys.stderr)
        sys.exit(1)
    if sys.argv[1:] == ["--gdscript"]:
        print("extends RefCounted\n\nconst DATA = " + payload)
    elif not sys.argv[1:]:
        print(payload)
    else:
        sys.exit("Usage: git_snapshot.py [--gdscript]")
