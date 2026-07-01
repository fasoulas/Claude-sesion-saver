---
name: claude-resume-setup
description: Install the named-session save/resume setup (claude() shell wrapper, claude-resume CLI, /rename hook, locked session-names.json) onto this machine. Use when the user asks to set up, install, or replicate session naming/resume on a new computer, or mentions "claude-resume setup" or this skill's bundled files.
---

# Install claude-resume setup

Installs everything from this skill's directory onto the current machine so
`claude` auto-prompts to name a session on exit, and `claude-resume` can
resume it later by name or via an fzf picker. Source of truth: the files
bundled alongside this SKILL.md (`bin/`, `lib/`, `hooks/`, `zshrc-snippet.sh`,
`settings.hook-snippet.json`). Full design notes are in `README.md` next to
this file — read it if anything below is ambiguous.

## Prerequisites — verify before installing

- `zsh` is the login shell (the wrapper uses `vared`, a zsh builtin; bash will not work)
- `python3` on PATH
- `fzf` on PATH (`brew install fzf` / `apt install fzf` if missing)
- `claude` CLI on PATH

Run all four checks; if any fail, tell the user what's missing and stop.

## Steps

1. **Copy the runtime files**, preserving relative layout, into `~/.claude/`:
   ```bash
   mkdir -p ~/.claude/bin ~/.claude/lib ~/.claude/hooks
   cp <skill_dir>/bin/claude-resume          ~/.claude/bin/claude-resume
   cp <skill_dir>/lib/session_map.py         ~/.claude/lib/session_map.py
   cp <skill_dir>/hooks/rename-session-hook.py ~/.claude/hooks/rename-session-hook.py
   chmod +x ~/.claude/bin/claude-resume
   ```
   (`<skill_dir>` is wherever this SKILL.md lives, e.g.
   `~/.claude/skills/claude-resume-setup`.)

2. **Merge the hook into `~/.claude/settings.json`.**
   - If `~/.claude/settings.json` doesn't exist, create it from
     `<skill_dir>/settings.hook-snippet.json`'s `hooks` block (drop the
     `_comment` key).
   - If it exists and has no `hooks.UserPromptSubmit` array, add one
     containing the single entry from the snippet.
   - If it exists and already has a `hooks.UserPromptSubmit` array, **append**
     the snippet's one entry (`{"matcher": "/rename", "hooks": [...]}`) to
     that array — do not overwrite existing entries, settings.json commonly
     has other unrelated hooks registered under the same event.
   - Use the Edit tool for this, not a blind overwrite, since the user's
     existing settings.json must be preserved.
   - Validate after editing:
     ```bash
     python3 -c "import json; json.load(open('$HOME/.claude/settings.json'))" && echo OK
     ```

3. **Append the shell wrapper to `~/.zshrc`.**
   - Check whether a `claude()` function already exists in `~/.zshrc` (or
     wherever it's symlinked to — resolve with `readlink -f ~/.zshrc` first,
     since it may be a dotfiles symlink; always edit the resolved target, not
     the symlink). If a `claude()` function is already defined, stop and ask
     the user how to reconcile rather than appending a conflicting second
     definition.
   - Otherwise, append the full contents of `<skill_dir>/zshrc-snippet.sh` to
     the end of the resolved `~/.zshrc` target.

4. **Reload and verify:**
   ```bash
   source ~/.zshrc   # or open a new terminal
   which claude-resume   # -> ~/.claude/bin/claude-resume
   type claude            # -> shows the shell function, not just a binary path
   ```

5. Report what was installed, and note that `~/.claude/session-names.json`
   and `~/.claude/session-names.json.lock` will be created automatically on
   first use — don't pre-create them.

## Do not

- Don't run destructive git/file operations as part of install.
- Don't overwrite an existing `~/.claude/settings.json` wholesale — merge only.
- Don't silently replace an existing `claude()` function in `.zshrc` — ask first.
