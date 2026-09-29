#!/usr/bin/env python3
"""Collate append-only feature notes at a git revision, or the working tree.

Usage: feature_notes.py titles|edge|validate [REV] (default WORKTREE).
No third-party packages; legacy lists remain readable across old release tags.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

PATTERN = re.compile(r"game/features/[^/]+/release_notes/[^/]+\.json$")
LEGACY = "game/features/changelog/entries.gd"


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def read(path, rev):
    if rev == "WORKTREE":
        return Path(path).read_text(encoding="utf-8") if Path(path).exists() else ""
    result = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    if result.returncode:
        # Missing files at historical tags are expected; invalid revisions aren't.
        git("rev-parse", "--verify", rev)
        return ""
    return result.stdout


def single_line(value):
    return isinstance(value, str) and bool(value.strip()) and not any(c in value for c in "\r\n")


def fragments(rev):
    if rev == "WORKTREE":
        paths = (str(p) for p in Path("game/features").glob("*/release_notes/*.json"))
    else:
        paths = git("ls-tree", "-r", "--name-only", rev).splitlines()
    result = {}
    for path in sorted(p for p in paths if PATTERN.fullmatch(p)):
        note = json.loads(read(path, rev))
        if not isinstance(note, dict) or set(note) - {"title", "summary", "notes"}:
            raise ValueError(f"{path}: expected title, summary and notes fields")
        for key in ("title", "summary"):
            if not single_line(note.get(key)):
                raise ValueError(f"{path}: {key} must be a nonempty single-line string")
        bullets = note.get("notes")
        if not isinstance(bullets, list) or not bullets or any(not single_line(b) for b in bullets):
            raise ValueError(f"{path}: notes must contain nonempty single-line strings, without bullet prefixes")
        if any(b.startswith(("- ", "* ")) for b in bullets):
            raise ValueError(f"{path}: notes must not include bullet prefixes")
        result[path] = note
    return result


def titles(rev):
    matches = re.findall(
        r'^\s*"title":\s*"((?:[^"\\]|\\.)*)",?\s*$', read(LEGACY, rev), re.M
    )
    legacy = [json.loads('"' + title + '"') for title in matches]
    all_titles = [n["title"] for n in fragments(rev).values()] + legacy
    if len(set(all_titles)) != len(all_titles):
        raise ValueError("duplicate release-note title; use a unique title per change")
    return all_titles


def latest_tag(rev):
    if rev == "WORKTREE" and subprocess.run(["git", "rev-parse", "--verify", "HEAD"], capture_output=True).returncode:
        return None
    tags = git(
        "tag", "--merged", "HEAD" if rev == "WORKTREE" else rev,
        "--list", "v[0-9]*.[0-9]*.[0-9]*", "--sort=-v:refname"
    ).splitlines()
    return tags[0] if tags else None


def edge(rev):
    tag = latest_tag(rev)
    old = fragments(tag) if tag else {}
    notes = fragments(rev)
    if old.keys() - notes.keys():
        raise ValueError("released feature notes must not be deleted or renamed")
    for path in notes.keys() & old.keys():
        if notes[path] != old[path]:
            raise ValueError(f"{path}: released notes are immutable; add a new file")
    raw = read("CHANGELOG.md", rev)
    section = re.search(r"^## \[edge\]\s*\n(.*?)(?=^## |\Z)", raw, re.M | re.S)
    legacy = section.group(1).strip() if section else ""
    fresh = [
        "- " + bullet
        for path, note in notes.items() if path not in old
        for bullet in note["notes"]
    ]
    return "\n".join(([legacy] if legacy else []) + fresh)


def main():
    if len(sys.argv) < 2:
        raise ValueError("usage: feature_notes.py titles|edge|validate [REV]")
    mode = sys.argv[1]
    rev = sys.argv[2] if len(sys.argv) > 2 else "WORKTREE"
    if mode == "titles":
        for title in titles(rev):
            print(json.dumps(title, ensure_ascii=False)[1:-1])
    elif mode == "edge":
        titles(rev)
        notes = edge(rev)
        if notes:
            print(notes)
    elif mode == "validate":
        titles(rev)
        edge(rev)
        print("Feature release notes are valid.")
    else:
        raise ValueError("usage: feature_notes.py titles|edge|validate [REV]")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
