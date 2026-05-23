# coding-toolkit — project notes

Personal Claude Code plugin. Source of truth for the coding-principles skill +
worktree-gate hook. Installed plugin path is read-only-ish; edit here, push,
reinstall.

## Design decisions

- **Skill vs hook split**: principles are advisory → on-demand skill; the
  worktree rule is a pre-edit gate → deterministic PreToolUse hook. Skills
  undertrigger and CLAUDE.md is advisory, so neither can guarantee a gate fires.
- **Warn-only hook**: never blocks (always exit 0). Injects a one-time
  per-session reminder. Warns even on a feature branch in the main checkout —
  multi-agent same-branch work still risks mixing trees; a *linked* worktree is
  the safe place and stays silent.
- **CLAUDE.md split**: Worktree Isolation + Auto-Rename stay full-text in
  `~/.agent-config/instructions.md` (always-on backup for the gate). Accuracy,
  Adversarial Review, Codex Rescue moved into the skill + a pointer note.

## Backlog / future improvements

- [ ] **Codex/Copilot coverage**: `~/.agent-config/sync.sh` mirrors
  `~/.claude/skills/*` to Codex/Copilot. The principles skill now lives in this
  plugin, not `~/.claude/skills/`, so Codex/Copilot don't get it. For now the
  skill tells the main agent to restate principles when dispatching subagents.
  If Codex/Copilot coverage matters later: extend sync.sh to also walk
  `~/.claude/plugins/*/skills/*` (and this repo's `skills/`), mirroring them the
  same way. Avoid symlinking into `~/.claude/skills/` — Claude Code would then
  load the skill twice (personal + plugin).
- [ ] **commands/**: add slash commands if a repeatable coding workflow emerges
  (e.g. `/scaffold-worktree`).
- [ ] **Hook config tunability**: per-repo opt-out (e.g. a `.coding-toolkit-off`
  marker) for solo repos where the worktree nudge is noise.
- [ ] **Marketplace listing**: if sharing publicly, add to a marketplace manifest.

## Local dev / test

```bash
# load for one session
claude --plugin-dir ~/Code/coding-toolkit

# unit-test the hook with mock stdin
echo '{"tool_input":{"file_path":"/tmp/repo/x.py"},"cwd":"/tmp/repo","session_id":"s1"}' \
  | hooks/worktree-gate.sh
```
