# --- Claude session save/resume: paste into ~/.zshrc (end of file is fine) ---

export PATH="$HOME/.claude/bin:$PATH"

claude() {
  local launch_cwd="$PWD"

  command claude "$@"
  local rc=$?

  # claude's TUI can leave the tty in raw/cbreak mode on exit; reset before
  # we read from it again (vared below), or the name prompt appears to hang.
  stty sane 2>/dev/null

  # Derive project dir from the cwd where claude was launched (matches Claude Code's own mapping)
  local proj_hash="-$(echo "$launch_cwd" | sed 's|^/||; s|/|-|g')"
  local proj_dir="$HOME/.claude/projects/$proj_hash"
  [[ -d "$proj_dir" ]] || return $rc

  # Most recently modified JSONL = the session that just ended (avoids last-session.json race)
  local latest_jsonl
  latest_jsonl=$(ls -t "$proj_dir"/*.jsonl 2>/dev/null | head -1)
  [[ -z "$latest_jsonl" ]] && return $rc

  local sid
  sid=$(basename "$latest_jsonl" .jsonl)
  [[ -z "$sid" ]] && return $rc

  # Skip naming entirely if no user message was ever sent (empty/no-action session)
  grep -qF '"type":"user"' "$latest_jsonl" 2>/dev/null || return $rc

  local map="$HOME/.claude/session-names.json"

  # JSONL custom-title is authoritative (set by /rename built-in) — check it first
  # grep is fast; we want the LAST title in case of multiple renames
  local existing_name
  existing_name=$(grep -F '"custom-title"' "$latest_jsonl" 2>/dev/null | python3 -c "
import json, sys
sid = '$sid'
title = None
for line in sys.stdin:
    try:
        d = json.loads(line)
        if d.get('type') == 'custom-title' and d.get('sessionId') == sid:
            title = d.get('customTitle', '').strip() or None
    except: pass
if title: print(title)
" 2>/dev/null)

  # Fallback: session-names.json (sessions named via vared prompt, not /rename)
  if [[ -z "$existing_name" ]]; then
    existing_name=$(python3 -c "
import json, sys
try:
    data = json.load(open('$map'))
    for n, v in data.items():
        if v.get('session_id') == '$sid':
            print(n); sys.exit(0)
except: pass
" 2>/dev/null)
  fi

  # Persist custom-title to session-names.json so claude-resume works
  if [[ -n "$existing_name" ]]; then
    PYTHONPATH="$HOME/.claude/lib" python3 - "$existing_name" "$sid" "$launch_cwd" <<'PYEOF'
import sys, datetime
from session_map import locked_map
name, sid, cwd = sys.argv[1:4]
with locked_map() as data:
    # Remove any stale entry for this session_id (handles renames)
    stale = [k for k, v in data.items() if v.get('session_id') == sid and k != name]
    for k in stale:
        del data[k]
    data[name] = {"session_id": sid, "cwd": cwd, "saved_at": datetime.datetime.now().isoformat()}
PYEOF
  fi

  if [[ -n "$existing_name" ]]; then
    echo "Session '$existing_name' saved. Resume with: claude-resume $existing_name"
  else
    # Build default name: <dirname>-YYYY-MM-DD, with -A/-B/... suffix if taken
    local base_name
    base_name="$(basename "$launch_cwd")-$(date +%Y-%m-%d)"
    local default_name
    default_name=$(python3 - "$map" "$base_name" <<'PYEOF'
import json, sys, string
map_file, base = sys.argv[1], sys.argv[2]
try:
    data = json.load(open(map_file))
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
if base not in data:
    print(base)
else:
    for letter in string.ascii_uppercase:
        candidate = f"{base}-{letter}"
        if candidate not in data:
            print(candidate); sys.exit(0)
    print(base)  # fallback if somehow all 26 taken
PYEOF
)

    local tmp_name
    tmp_name=$(python3 - "$map" <<'PYEOF'
import json, sys, string
map_file = sys.argv[1]
try:
    data = json.load(open(map_file))
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
for letter in string.ascii_uppercase:
    candidate = f"tmp_{letter}"
    if candidate not in data:
        print(candidate); sys.exit(0)
print("tmp_Z")
PYEOF
)

    local name="$default_name"
    vared -p "Name this session for later --resume (Enter for $tmp_name): " name
    [[ -f "$map" ]] || echo '{}' > "$map"
    if [[ -z "$name" ]]; then
      name="$tmp_name"
    fi
    PYTHONPATH="$HOME/.claude/lib" python3 - "$name" "$sid" "$launch_cwd" <<'PYEOF'
import sys, datetime
from session_map import locked_map
name, session_id, cwd = sys.argv[1:4]
with locked_map() as data:
    data[name] = {"session_id": session_id, "cwd": cwd, "saved_at": datetime.datetime.now().isoformat()}
PYEOF
    if [[ "$name" == tmp_* ]]; then
      echo "Auto-saved as '$name' (no name given). Resume with: claude-resume $name"
    else
      echo "Saved as '$name'. Resume with: claude-resume $name"
    fi
  fi

  return $rc
}
