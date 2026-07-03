# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Not an app — an installable Claude Code **skill package**. It bundles a `claude()` zsh
wrapper, a `claude-resume` CLI, a `claude-search` CLI, and a `/rename` hook that
together let a user name a Claude Code session on exit, resume it later by name (or
via `fzf`), or find a past session by what was said in it. The repo's own
root is the skill source; end users copy its contents into `~/.claude/{bin,lib,hooks}`
and merge `settings.hook-snippet.json` + `zshrc-snippet.sh` into their own dotfiles.

No build system, package manager, linter, or test suite — this is plain bash + a couple
of small stdlib-only Python scripts. There is nothing to `npm install` or `pip install`.

## Validating changes

- Syntax-check the shell wrapper: `bash -n zshrc-snippet.sh` and `bash -n bin/claude-resume`
- Syntax-check Python: `python3 -m py_compile lib/session_map.py hooks/rename-session-hook.py bin/claude-search`
- Validate JSON snippet: `python3 -c "import json; json.load(open('settings.hook-snippet.json'))"`
- `claude-search`'s pure logic (text extraction, snippet building) has a standalone
  self-check: `python3 bin/test_claude_search.py`
- Beyond that there's no automated test harness — verify behavior manually by
  installing into a scratch `~/.claude` (or a temp `HOME`) and exercising `claude`,
  `/rename`, `claude-resume`, and `claude-search` end-to-end.

## Architecture

Full flow diagram: `architecture.mmd` (also embedded in `README.md`). The short version:

- **`lib/session_map.py`** is the single point of truth for reading/writing
  `~/.claude/session-names.json` (the `name -> {session_id, cwd, saved_at}` map). Its
  `locked_map()` context manager holds an `flock` on a sibling `.lock` file for the
  entire read-modify-write, because three independent, uncoordinated writers touch the
  same file:
  1. the `claude()` zsh function (`zshrc-snippet.sh`) — on every `claude` exit
  2. `hooks/rename-session-hook.py` — fires on `/rename <name>` via a `UserPromptSubmit`
     hook (wired through `settings.hook-snippet.json`, matcher `/rename`)
  3. `bin/claude-resume`'s own sync pass — on every resume invocation
- **`zshrc-snippet.sh`** defines `claude()`, which shadows the real `claude` binary.
  After the real binary exits it finds the most recently modified `.jsonl` transcript
  in `~/.claude/projects/<hashed-cwd>/`, skips naming entirely if the transcript has no
  user message, looks for an existing name (via the transcript's `custom-title` record
  written by the built-in `/rename`, or a prior `session_id` match in
  `session-names.json`), and otherwise interactively prompts (`vared`, zsh-only) for a
  name — defaulting to `<dirname>-YYYY-MM-DD` with `-A`/`-B`/... collision suffixes, or
  `tmp_X` on empty input.
- **`bin/claude-resume [name]`** re-syncs the map before doing anything: prunes entries
  whose saved `cwd` no longer exists, prunes entries whose transcript `.jsonl` is gone,
  and re-checks each transcript's `custom-title` against the stored name (renaming the
  map key if they've diverged). With no `name` argument it renders a numbered/aligned
  table (`# | NAME | PATH | SAVED_AT`) through `fzf`. It then `cd`s into the session's
  saved `cwd` and `exec`s `claude --resume <session_id>`. `--delete <name|#>` removes an
  entry by name or by the picker's numeric index.
- **`bin/claude-search QUERY`** is read-only (no `locked_map()`, no lock needed): it
  globs every `~/.claude/projects/*/*.jsonl`, extracts text from `user`/`assistant`
  messages (handling both plain-string and content-block-list message shapes — the
  latter mixes `text` and `tool_result` blocks; only `text` blocks are searched),
  matches against the query, and renders one deduped row per session (most recent
  match wins) as an aligned table matching `claude-resume`'s picker shape (`#`,
  `NAME`, `PATH`, `WHEN`, `SNIPPET`), resolving a friendly name via
  `session-names.json` when one exists. Each row carries `session_id`/`cwd` as
  hidden trailing tab fields so that, when piped into `fzf` (interactive tty +
  `fzf` on `PATH`), the selected row can be resumed directly — `cd` into the saved
  `cwd`, `os.execvp("claude", ["claude", "--resume", session_id])` — without a
  second lookup through `session-names.json`. `--list` (or non-tty output) skips
  `fzf` and just prints the table.
- **`hooks/rename-session-hook.py`** is the `UserPromptSubmit` hook target: parses
  `/rename <name>` out of the submitted prompt JSON (stdin) and writes/overwrites the
  entry for the current `session_id` via `locked_map()`.
- **`SKILL.md`** is what makes this directory usable as a Claude Code skill itself —
  when a user asks to "install claude-resume setup," Claude follows `SKILL.md`'s steps
  to copy the runtime files into `~/.claude/`, *merge* (never overwrite) the hook into
  the user's existing `settings.json`, and append the wrapper to `~/.zshrc` (asking
  first if a conflicting `claude()` already exists there).

## Constraints worth knowing before editing

- The `claude()` wrapper requires **zsh** specifically (`vared` has no bash equivalent) —
  don't "fix" it into POSIX sh.
- Project directory hashing in `zshrc-snippet.sh` (`-$(echo "$cwd" | sed 's|^/||; s|/|-|g')`)
  must keep matching Claude Code's own `~/.claude/projects/<hash>` naming scheme — if
  Claude Code changes that scheme, this breaks silently (sessions just won't be found).
- Any change to the on-disk shape of `session-names.json` entries must stay consistent
  across all three writers (`zshrc-snippet.sh`, `rename-session-hook.py`,
  `bin/claude-resume`'s sync pass) plus the reader in `bin/claude-resume`'s picker/lookup
  logic — they currently assume `{session_id, cwd, saved_at}` exactly.
- Runtime state files (`~/.claude/session-names.json`, `.lock`) are created lazily on
  first use and are intentionally *not* part of the repo/install — don't add
  pre-creation logic.
