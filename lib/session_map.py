"""Shared locked read-modify-write access to ~/.claude/session-names.json.

Three independent writers (zsh claude() wrapper, rename-session-hook.py,
claude-resume's sync pass) touch this file. Without a lock, two near-
simultaneous writes can clobber each other.
"""

import contextlib
import fcntl
import json
import os

MAP_FILE = os.path.expanduser("~/.claude/session-names.json")
LOCK_FILE = MAP_FILE + ".lock"


@contextlib.contextmanager
def locked_map():
    """Yield the map dict; writes it back on clean exit. Holds an exclusive lock throughout."""
    lock_fd = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX)
        try:
            with open(MAP_FILE) as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            data = {}
        yield data
        with open(MAP_FILE, "w") as f:
            json.dump(data, f, indent=2)
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()
