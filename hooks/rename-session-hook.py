#!/usr/bin/env python3
"""UserPromptSubmit hook: detect /rename <name> and persist to session-names.json."""

import json, sys, os, datetime, re

sys.path.insert(0, os.path.expanduser("~/.claude/lib"))
from session_map import locked_map

data = json.load(sys.stdin)
prompt = data.get("prompt", "").strip()
session_id = data.get("session_id", "")

m = re.match(r"^/rename\s+(.+)$", prompt)
if not m or not session_id:
    sys.exit(0)

name = m.group(1).strip()
if not name:
    sys.exit(0)

cwd = data.get("cwd", os.getcwd())
with locked_map() as sessions:
    sessions[name] = {
        "session_id": session_id,
        "cwd": cwd,
        "saved_at": datetime.datetime.now().isoformat(),
    }

sys.exit(0)
