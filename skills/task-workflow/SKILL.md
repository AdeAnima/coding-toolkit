---
name: task-workflow
description: >-
  Project task management for a repo: epics, milestones, and feature-sized PM
  tasks tracked as one markdown note per task in a local Obsidian vault, queried
  via Obsidian Bases. Use this whenever you are planning project work, picking
  what to build next, tracking feature/epic/milestone status, grooming a
  backlog, or recording that a feature is done — i.e. the layer ABOVE a single
  implementation. It hands off each PM task into the superpowers
  brainstorm → spec → plan → execute loop and records the resulting spec/plan
  file links. Consult it when the user says "what should I work on", "add a
  feature/epic/milestone", "track this", "what's the status", "groom the
  backlog", or starts a new piece of project work.
---

# Task Workflow

The **durable** project-management layer for a repo. It tracks *what work
exists and where it stands* across many features over time. It is distinct from
— and feeds into — the **ephemeral** superpowers implementation loop.

## The one rule that prevents the most damage

**A PM task is a feature-sized story (1–N days). A superpowers plan step is a
2–5 minute checkbox. They are different layers. Never create a PM note per plan
step.** One PM task → one spec file → one plan file containing 10–30 steps.
Getting this wrong floods the vault with dozens of notes per feature and makes
Bases useless.

## Layers and ownership (the seam)

| Layer | Unit | Lives in | Tracked by | Durable |
|-------|------|----------|------------|---------|
| **PM** (this skill) | feature-sized task / epic / milestone | one Obsidian note + YAML frontmatter | Obsidian Bases | yes |
| **Implementation** (superpowers) | 2–5 min step | `docs/superpowers/plans/*.md` checkbox | TodoWrite | no |

Ownership contract — do not duplicate content across layers:

- **PM note** owns: what, why, acceptance criteria, `status`, and links out.
- **Spec file** (`docs/superpowers/specs/…`) owns: the design.
- **Plan file** (`docs/superpowers/plans/…`) owns: the how (steps).

The PM note links forward via `spec_file:` / `plan_file:`. Spec/plan files may
back-reference `pm_task:` for provenance. The PM note's `status` is the single
field the agent advances as it walks the superpowers loop.

## Vault layout

A local Obsidian vault lives at `pm/` in the repo root:

```
pm/
  .obsidian/            # vault config (gitignored except community plugin list)
  tasks/                # one note per PM task: T-NNN.md
  epics/                # one note per epic: epic-<slug>.md
  milestones/           # one note per milestone: m-<slug>.md
  archive/              # done tasks moved here after they settle
  board.base            # group-by-status view of tasks/
  backlog.base          # status=backlog, priority column first (sort in UI)
```

`archive/` exists from day one: move a task note here once it has been `done`
for a while. Bases editing performance degrades past several hundred notes, so
keep `tasks/` to live work only.

## Status lifecycle

A PM task's `status` advances through the superpowers loop:

```
backlog → speccing → planning → in-progress → review → done
```

- `backlog` — captured, not started.
- `speccing` — running superpowers `brainstorming`; produces the spec file.
- `planning` — running superpowers `writing-plans`; produces the plan file.
- `in-progress` — running `executing-plans` / `subagent-driven-development`.
- `review` — code green, running adversarial review / finishing the branch.
- `done` — merged. Eligible for `archive/`.

`blocked` and `cancelled` are terminal/holding states usable from any point.

## How to use it

The helper lives at `${CLAUDE_PLUGIN_ROOT}/skills/task-workflow/scripts/tw.sh`
(same path the `/tw` command uses; resolves wherever the plugin is installed).
Examples below abbreviate it as `tw`; run it with that full path (or alias it).
It operates on the `pm/` vault under the **current repo**, so run it from inside
the target repo.

### Preflight: ensure the vault exists (do this first, every time)

Before the first PM action in a repo, check whether the vault is set up — do not
leave it to the user to remember:

1. Check for `pm/` in the repo root (e.g. `test -d pm`). Every `tw` subcommand
   except `init` also self-reports: it exits non-zero with
   `tw: run 'tw.sh init' first` when the vault is missing.
2. **If `pm/` is absent:** tell the user there's no task-workflow vault in this
   repo yet and ask whether to create one, naming what `tw init` will do
   (creates `pm/{tasks,epics,milestones,archive}` + `board.base` + `backlog.base`).
   Wait for a yes — do not scaffold files unasked.
3. **On yes:** run `tw init` yourself, then proceed with the requested action.
   **On no:** stop; don't run PM commands that would fail.

`tw init` is idempotent (`mkdir -p`, `cp -n`) — safe to run if unsure whether a
partial vault exists. It does **not** launch Obsidian or require it to be
running; the vault is plain files. Opening it in Obsidian (and enabling the
Bases core plugin on first open) is a manual, human-side step.

### Pick what to build next
Run `tw next` — prints the highest-priority `backlog` task (ties broken by oldest
`created`). Or open `backlog.base` in Obsidian.

### Start a task → hand off to superpowers
1. `tw status T-042 speccing`
2. Invoke **superpowers `brainstorming`**. When it writes the spec to
   `docs/superpowers/specs/…`, record it: `tw link T-042 spec <path>`.
3. `tw status T-042 planning`; invoke **superpowers `writing-plans`**;
   record the plan: `tw link T-042 plan <path>`.
4. `tw status T-042 in-progress`; invoke **superpowers
   `executing-plans`** (or `subagent-driven-development`).
5. `tw status T-042 review`; finish the branch + adversarial review
   per the `coding-principles` skill.
6. `tw status T-042 done`.

### Capture new work
- `tw new task "CSV export" --epic epic-export --milestone m1-ga --priority 2`
- `tw new epic "Data export"`
- `tw new milestone "GA"`

### Validate before relying on Bases
`tw check` — flags malformed frontmatter, unknown `status` values,
and dangling `epic:` / `milestone:` wikilinks. Run after bulk edits; Bases
silently drops rows whose frontmatter doesn't parse.

## Frontmatter agents must write correctly

Bases reads YAML frontmatter one note = one row. Get the types right or the row
vanishes from views:

- `status` — one of the lifecycle values above, **unquoted bare word** is fine
  but stay exact (`in-progress`, not `In Progress`).
- `priority` — number `1`–`3` (1 highest), unquoted.
- `created` — ISO 8601 date `YYYY-MM-DD`, unquoted.
- `epic` / `milestone` — wikilink **inside quotes**: `"[[epic-export]]"`.
- `spec_file` / `plan_file` — repo-relative path string, may be empty.

Use the templates in `templates/` rather than writing frontmatter from memory.

## Dependencies

- **Obsidian primitives** come from the `kepano/obsidian-skills` plugin (Bases,
  markdown, frontmatter). Adopt it for `.base` authoring details rather than
  re-deriving Bases YAML here.
- The implementation loop is **superpowers** (`brainstorming`, `writing-plans`,
  `executing-plans`, `finishing-a-development-branch`). This skill only manages
  the PM layer and the handoff; it does not re-implement planning.
- `tw.sh` needs only `git` plus POSIX `awk`/`sed` — no `yq`. The frontmatter
  schema is flat, so a line-oriented reader suffices and stays portable.
