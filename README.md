# coding-toolkit

Personal [Claude Code](https://code.claude.com) plugin with coding guardrails.
Bundles engineering judgment as an on-demand skill plus a deterministic worktree
nudge as a hook — matching each rule to the mechanism that actually enforces it.

## What's inside

| Component | Type | Loads | Purpose |
|-----------|------|-------|---------|
| `coding-principles` | skill | on-demand, when doing code work | DRY / YAGNI / KISS / SINE as decision heuristics, accuracy discipline, milestone adversarial review, Codex delegation guidance |
| `task-workflow` | skill | on-demand, when planning/tracking project work | durable PM layer: epics/milestones/feature-tasks as one note per task in an Obsidian vault, queried via Bases, handing off into the superpowers implementation loop |
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

### Task workflow

A durable project-management layer that sits *above* the per-feature
implementation loop. Work is tracked as **one markdown note per feature-sized
task** in a local Obsidian vault at `pm/`, with epics and milestones as their
own notes, all queried via Obsidian Bases (`board.base`, `backlog.base`).

The key distinction: a **PM task** (1–N days, one note, Bases-queryable) is *not*
a **plan step** (2–5 min checkbox, ephemeral, owned by superpowers). One PM task
→ one spec file → one plan file. The skill walks a task through
`backlog → speccing → planning → in-progress → review → done`, handing off to the
superpowers `brainstorming` → `writing-plans` → `executing-plans` loop and
recording the resulting `spec_file` / `plan_file` links.

The `scripts/tw.sh` helper drives it from the command line:

```bash
tw.sh init                                    # scaffold pm/ vault + .base views
tw.sh new task "CSV export" --epic epic-export --priority 2
tw.sh next                                    # highest-priority backlog task
tw.sh status T-001 in-progress
tw.sh link T-001 spec docs/superpowers/specs/2026-05-23-csv-design.md
tw.sh check                                   # validate frontmatter for Bases
```

Obsidian primitives (Bases authoring) come from the
[`kepano/obsidian-skills`](https://github.com/kepano/obsidian-skills) plugin;
the implementation loop is [superpowers](https://github.com/anthropics/claude-code).
This skill owns only the PM layer and the handoff.

## Install

The repo is its own marketplace. In Claude Code:

```
/plugin marketplace add AdeAnima/coding-toolkit
/plugin install coding-toolkit@coding-toolkit
```

Update later with `/plugin marketplace update coding-toolkit` then reinstall.

For local development on the plugin itself, load the working copy for one
session without installing:

```bash
claude --plugin-dir /path/to/coding-toolkit
```

## Requirements

- `git` and `jq` on PATH (the hook fails open — stays silent — if `jq` is
  missing).
- `task-workflow` uses `git` and standard POSIX tools (`awk`/`sed`); no `yq`
  required. Obsidian (with Bases, v1.9+) to view the vault.

## License

MIT — see [LICENSE](LICENSE).
