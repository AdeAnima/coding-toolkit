# coding-toolkit

Personal [Claude Code](https://code.claude.com) plugin with coding guardrails.
Bundles engineering judgment as an on-demand skill plus a deterministic worktree
nudge as a hook — matching each rule to the mechanism that actually enforces it.

## What's inside

| Component | Type | Loads | Purpose |
|-----------|------|-------|---------|
| `coding-principles` | skill | on-demand, when doing code work | DRY / YAGNI / KISS / SINE as decision heuristics, accuracy discipline, milestone adversarial review, Codex delegation guidance |
| `worktree-gate` | PreToolUse hook | every `Edit`/`Write`, deterministic | warn-only nudge to isolate edits in a git worktree |

### Why split skill vs hook

- **Principles are guidance** — fine to load lazily when the model recognizes
  code work. A skill keeps them out of context for non-coding chats.
- **The worktree nudge is a gate** — it has to fire *before* an edit, every time,
  regardless of whether a skill triggered. Only a hook guarantees that. Skills
  undertrigger; advisory memory is ignorable.

### Worktree gate behavior

Fires on `Edit`/`Write`/`MultiEdit`/`NotebookEdit`. Injects a one-time
per-session reminder when you're editing the **main working tree** of a git repo
instead of an isolated worktree — including on a feature branch, since multiple
agents can share a branch and a shared checkout mixes their work.

It is **warn-only**: never blocks, always exits 0. Silent inside a linked
worktree, in non-git directories, and after the first warning each session.

## Install

Clone, then add to a marketplace and enable:

```bash
git clone https://github.com/AdeAnima/coding-toolkit.git
# in Claude Code:
/plugin marketplace add /path/to/coding-toolkit
/plugin install coding-toolkit
```

Or load for a single session during development:

```bash
claude --plugin-dir /path/to/coding-toolkit
```

## Requirements

- `git` and `jq` on PATH (the hook fails open — stays silent — if `jq` is
  missing).

## License

MIT — see [LICENSE](LICENSE).
