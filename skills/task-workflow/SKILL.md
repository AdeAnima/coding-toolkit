---
name: task-workflow
description: >-
  Project task management for any coding repo: epics, milestones, and
  feature-sized tasks tracked as one markdown note per task in a local Obsidian
  vault, queried via Obsidian Bases. This is the durable layer ABOVE a single
  implementation — it owns what work exists and where it stands, then hands each
  task into the superpowers brainstorm → spec → plan → execute loop and records
  the spec/plan links. Use it whenever the user is choosing or prioritising what
  to work on next, grooming or triaging the backlog, adding a
  feature/epic/milestone, or starting any new feature-sized piece of work. Also
  applies when a repo already tracks work in an informal tracker (project.md,
  ROADMAP.md, TODO.md, KNOWN_ISSUES.md, etc.) but has no pm/
  vault. Invoke this skill to handle these — do not read tracker files or probe
  pm/ yourself; the skill owns detection, ranking, and migration.
  NOT for a
  one-off typo or single-file bugfix, a two-minute tweak, or ticking an
  in-flight plan checkbox — those stay in the plan.
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

### Preflight: let the script gate you (do this first, every time)

**Do not hand-detect vault state.** Do not run `test -d pm/...` yourself and do
not scan the repo for tracker files yourself. The `tw.sh` script is the gate: it
detects the vault, detects a foreign tracker, and prints the directive that tells
you what to do. If you reimplement that detection in your own Bash, you skip the
gate and freelance a backlog — the exact failure this preflight exists to stop.

1. **Run the requested subcommand through the script and read its exit code.**
   For "what's next / what should I build" that is `tw.sh next`; for a capture
   it is the `tw.sh new …` the user asked for. Run it and branch on the result:
   - **Exit 0** → vault exists and the command did its job. Use the output. Done.
   - **Non-zero with a STOP/HALT migration directive on stderr** (repo has a
     foreign tracker but no vault) → **obey that directive exactly**: ask the
     user the single migrate-vs-just-this-once question and wait. Do not read the
     tracker, do not rank tasks, do not run anything else until they answer. On
     "migrate" → go to **Migrating an existing tracker**. First, though, check
     the opt-out flag (below): if set, skip the migrate pitch and go to step 2.
   - **Non-zero with `tw: run 'tw.sh init' first`** (no vault, no foreign
     tracker) → go to step 2.
2. **Offer a bare init.** Tell the user there's no task-workflow vault in this
   repo yet and ask whether to create one, naming what `tw init` will do
   (creates `pm/{tasks,epics,milestones,archive}` + `board.base` + `backlog.base`).
   Wait for a yes — do not scaffold files unasked. **On yes:** run `tw.sh init`
   yourself, then re-run the original subcommand. **On no:** stop; don't run
   PM commands that would fail.

`tw init` is idempotent (`mkdir -p`, `cp -n`) — safe to run if unsure whether a
partial vault exists. It does **not** launch Obsidian or require it to be
running; the vault is plain files. Opening it in Obsidian (and enabling the
Bases core plugin on first open) is a manual, human-side step.

### Migrating an existing tracker

When step 2 finds a foreign tracker and no opt-out flag, offer to migrate it into
the PM vault. Migration is **propose → approve → run**: nothing touches the vault
until the user signs off, and the source tracker file is **never modified** (it
stays as the audit trail).

1. **Tell the user what you found** (which tracker file) and offer to migrate it
   into a `pm/` vault. **Ask how much control they want** — adapt to the answer:
   - *Auto:* run the whole migration, then show a summary.
   - *Propose-confirm (default):* show the proposed `tw new …` command list, run
     it only after the user approves.
   - *Interactive:* walk item by item, confirming each before adding it.
   If the user declines migration entirely, write the opt-out flag (below) and
   fall back to the bare-init offer.
2. **On confirm: scaffold first.** Run `tw init` to create the empty vault.
3. **Dispatch a migration sub-agent.** Use the **Agent** tool with
   `subagent_type: general-purpose` and `model: opus` — migration is a one-shot
   that defines the vault's whole epic/milestone structure, so classification
   errors propagate into every downstream link. Use the strongest model; do not
   let it inherit a weaker one. Dispatch it with this prompt (fill in the source
   path and the `tw.sh` path):

   > Read `<source tracker path>`. Classify each work item as a task, epic, or
   > milestone. Output a list of shell commands. **Order matters: emit every
   > `new epic` / `new milestone` line BEFORE any task that references it.**
   >
   > - Epics: `<tw.sh path> new epic "Title" --slug epic-<short-slug>`
   > - Milestones: `<tw.sh path> new milestone "Title" --slug m-<short-slug>`
   > - Tasks: `<tw.sh path> new task "Title" [--epic epic-<short-slug>] [--milestone m-<short-slug>] [--priority N]`
   >
   > The `--slug` you give an epic/milestone is its full id; reference that exact
   > string in each task's `--epic`/`--milestone`. Choose short, stable slugs
   > (`epic-rpc-shape`, not the whole title) and use them consistently — this is
   > what keeps task links from dangling. Infer grouping and priority from the
   > source structure. Output ONLY the command list as your final message — do
   > NOT run any command and do NOT edit the source file. Preserve source ordering
   > within each kind.

   It returns the command list as its final message.
4. **Main thread applies the result** per the chosen control level: show the
   command list (propose-confirm/interactive) or just run it (auto). Run each
   command from the repo root, **epics/milestones first** so task `--epic`
   references resolve. Then `tw check` to confirm the vault parses with no
   dangling links.
5. **Offer to open the vault in Obsidian.** Once `tw check` is clean, ask the
   user whether to open the new `pm/` vault now. **On no**, leave it — the files
   are already on disk. **On yes**, register and open it correctly:

   > **`open -a Obsidian "<path>"` does NOT register or switch to a new vault** —
   > it only re-focuses Obsidian on whatever vault was last active. A vault
   > Obsidian has never seen must be added to its registry first. Do not loop on
   > `open -a`; it will keep landing on the wrong vault.

   - **macOS** — edit the registry while Obsidian is quit, then relaunch:
     1. Quit Obsidian (`osascript -e 'quit app "Obsidian"'`, then `pkill -x Obsidian` if needed) so it doesn't overwrite the file on exit.
     2. In `~/Library/Application Support/obsidian/obsidian.json`, add an entry under `vaults`: a fresh random hex id → `{ "path": "<abs vault path>", "ts": <epoch-ms>, "open": true }`, and set `open: false` on every other vault so the new one is the one that opens.
     3. Relaunch: `open -a Obsidian`.
   - **Linux/Windows or if unsure** — don't poke the registry; tell the user to
     add it by hand once: Obsidian → vault switcher (bottom-left) → *Open folder
     as vault* → select the vault path. After that one-time step it stays
     registered.

   Bases ships **enabled by default** in current Obsidian, so `board.base` /
   `backlog.base` render on first open with no action. If an older Obsidian shows
   them as plain files, the user enables it once: Settings → Core plugins → Bases.
   First open may also prompt *Trust author* — that is expected; confirm it.

6. **Offer to archive the migrated source tracker (optional).** The source file
   was never modified during migration and stays as the audit trail — but it is
   now superseded by the vault, and a future session may read the stale tracker
   instead of the vault. After the user has the vault open, offer to tidy it.
   **Only on yes**, and never deleting:
   - `git mv <tracker> docs/legacy/<tracker>` (a move preserves git history; do
     **not** `rm`). Move only the trackers that were actually migrated — leave
     design/spec/brand docs (`DESIGN.md`, `PRODUCT.md`, …) where they are.
   - Drop a `docs/legacy/README.md` stub: one line saying these files are a frozen
     audit trail, the date migrated, and that `pm/` is now the source of truth.
   - If the vault is at the repo root (see below), add `docs/legacy/` to the
     Obsidian `userIgnoreFilters` so the archived trackers don't clutter the view.
   If the user prefers the tracker visible at root for history, skip this — it is
   a convenience, not a requirement.

**Vault at `pm/` (default) vs. the repo root.** This skill defaults to a vault
scoped to `pm/` — bounded, so Obsidian never treats stray repo `.md` as PM notes
and no exclude filters are needed. Some users instead want the **whole repo** as
the vault (to browse all project notes in Obsidian). That works, but it is a
manual reconfiguration, not a `tw` mode: move `.obsidian/` from `pm/` up to the
repo root, and in `.obsidian/app.json` set `userIgnoreFilters` to hide noise
(`node_modules/`, `dist/`, `build/`, `out/`, `coverage/`, `.git/`,
`.claude/worktrees/`) and `showUnsupportedFiles: false`. `tw.sh` is unaffected —
it only touches `pm/tasks` and `pm/*.base`, wherever the vault config lives. Gitignore
the root `.obsidian/workspace*` / `cache` local state but commit `app.json` /
`core-plugins.json`.

### Opt-out flag (so the migration prompt never nags)

Stored in `.claude/coding-toolkit.local.md` at the **target repo** root (shared
across this plugin's skills, so use a scoped key). It is a local preference, not
shared state: when you write it, also ensure the repo ignores it — add
`.claude/*.local.md` to the repo's `.gitignore` if not already present (create
`.gitignore` with that line if the repo has none). It silences the **prompt**,
not the **detection**.

- **Read:** before pitching migration, check the file for
  `task_workflow.migrate_declined: true` in its YAML frontmatter (Read the file,
  or `grep`). If set → do not pitch migration; proceed with the bare-init offer.
- **Write on decline:** if the user says they don't want to migrate, create or
  update `.claude/coding-toolkit.local.md` with:

  ```yaml
  ---
  task_workflow.migrate_declined: true
  ---
  ```

  Preserve any existing frontmatter keys other skills wrote — merge, don't clobber.
- **If the user later asks how to migrate** (explicitly), tell them: delete that
  key (or run migration directly via the steps above). Do **not** volunteer this
  reminder unprompted on every PM call — the whole point of the flag is silence.

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
