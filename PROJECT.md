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

### Phase 2 — task-workflow (durable PM layer)

- **Two layers, one seam.** `task-workflow` tracks *what work exists and its
  status* (durable). superpowers tracks *implementation steps within one feature*
  (ephemeral). A **PM task** = feature-sized story = one note; a **plan step** =
  2–5 min checkbox in a superpowers plan file. One PM task → one spec → one plan.
  Never a PM note per step. Linking is one-way forward: PM frontmatter carries
  `spec_file:` / `plan_file:`.
- **One note per task, not one file per epic.** Research (two independent agents)
  + the constraint that Obsidian Bases reads frontmatter one-note-per-row forced
  this: epic-as-file makes Bases blind to tasks and serialises every status flip
  into an epic-file rewrite. Reverses the earlier "one file per epic" pick —
  confirmed with the user.
- **Bases has no native kanban**; `board.base` groups a table by `status` as the
  poor-man's board. `backlog.base` sorts `status==backlog` by priority then age
  to drive `tw.sh next`.
- **No yq dependency.** Frontmatter schema is flat and fixed, so `tw.sh` reads
  with `sed`/`awk` (KISS). `fm_get` strips inline `# comment` guidance so values
  stay Bases-clean; `scrub_fm_comments` cleans created notes.
- **Dependencies, not re-implementation.** Obsidian Bases authoring → adopt
  `kepano/obsidian-skills`. Implementation loop → superpowers. This skill owns
  only the PM schema, lifecycle, and handoff.

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
- [ ] **Bases >500 notes degrades** (anecdotal, unbenchmarked). Solo repo is
  fine, but `tw.sh` should grow an `archive` command that moves `done` notes
  older than N days from `tasks/` to `archive/` so live views stay fast. The
  `archive/` folder + `check` already scan it; the mover is the missing piece.
- [ ] **kepano/obsidian-skills adoption**: not yet installed locally. Document as
  a soft dependency (Bases authoring reference); decide whether to bundle a
  pointer or rely on the user installing it separately.
- [ ] **tw.sh on PATH**: skill calls `scripts/tw.sh` relative to the plugin root;
  consider a `${CLAUDE_PLUGIN_ROOT}` shim or a `/tw` slash command so agents
  don't hard-code the worktree-relative path.

## Local dev / test

```bash
# load for one session
claude --plugin-dir ~/Code/coding-toolkit

# unit-test the hook with mock stdin
echo '{"tool_input":{"file_path":"/tmp/repo/x.py"},"cwd":"/tmp/repo","session_id":"s1"}' \
  | hooks/worktree-gate.sh
```
