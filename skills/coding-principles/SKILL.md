---
name: coding-principles
description: >-
  Engineering judgment for writing and changing code: the four fundamental dev
  principles (DRY, YAGNI, KISS, SINE), accuracy discipline (never guess APIs),
  when to run an adversarial review at a milestone, and when to delegate
  implementation to Codex. Consult this whenever you are about to write,
  edit, implement, refactor, fix, or review code — including bug fixes, new
  features, adding a function or class, restructuring, or reviewing a diff or
  PR. Use it even when the user only says "fix this", "add X", "clean this up",
  or names a language/framework, and don't wait to be told to apply the
  principles.
---

# Coding Principles

Decision heuristics for code work — not commandments. Each carries its *why* so
you can tell when it applies and when forcing it would do harm. Apply judgment;
these resolve tradeoffs, they don't replace thinking.

## The four fundamentals

### DRY — Don't Repeat Yourself
Write a piece of knowledge once so a change lands in one place, not five.

- **Why**: duplicated logic drifts — one copy gets fixed, the others rot into bugs.
- **Heuristic — Rule of Three**: extract on the *third* occurrence, not the first.
  Two similar lines may be coincidence; three is a pattern worth a name.
- **Anti-pattern**: premature abstraction. De-duplicating two things that only
  *look* alike couples them, so the next change has to fight the abstraction.
  Duplication is cheaper than the wrong abstraction — prefer a little copy-paste
  over a forced shared helper.

### YAGNI — You Aren't Gonna Need It
Build what the current task needs. Not the speculative future.

- **Why**: code written for hypothetical needs is untested, unused weight that
  still has to be read, maintained, and worked around.
- **Heuristic**: implement the requirement in front of you. If a future need is
  *known and imminent*, leave a seam (a clean boundary), not a full
  implementation.
- **Anti-pattern**: gold-plating config flags, plugin systems, or generic layers
  for one caller. Refactor to clarify *today's* code, not to host tomorrow's.

### KISS — Keep It Simple
Reach for the simplest design that solves the problem. Then refactor.

- **Why**: simple code is easier to read, debug, and change next week — and most
  of a system's life is "next week", not the moment it was written.
- **Heuristic**: between two approaches, pick the one that's *easiest to change
  later*, not the one that's cleverest now. Clever is a liability under
  maintenance.

### SINE — Simple Is Not Easy
A simple solution costs more effort to produce than a complex one. Spend it.

- **Why**: the first thing that works is usually tangled. Distilling it to
  something simple is real work — the payoff is everyone after you pays less.
- **Heuristic**: when the first cut works but feels knotty, that's the *start* of
  the job, not the end. Budget a pass to simplify before calling it done.

These pull against each other on purpose. DRY says unify; YAGNI and KISS say
don't unify prematurely. The skill is reading which tension wins *here*.

When dispatching implementer subagents (Codex rescue, general-purpose, builder),
restate these principles in the brief — subagents don't inherit this skill's
context, so spell out DRY/YAGNI/KISS/SINE and "verify before done" explicitly.

## Working habits — reduce common mistakes

The four fundamentals above are the *why*; these are the operational moves that
enact them at the keyboard. They bias toward caution over speed — for trivial
edits, use judgment. Merge with project-specific instructions as needed.

### Think before coding — don't assume, don't hide confusion

- State your assumptions explicitly. If uncertain, ask — a wrong assumption
  compounds through everything built on it.
- If multiple interpretations exist, present them; don't silently pick one.
- If a simpler approach exists, say so, and push back when warranted.
- If something is unclear, stop, name what's confusing, and ask — before coding,
  not after the mistake.

### Simplicity first — minimum code that solves the problem

The operational edge of KISS/YAGNI: nothing speculative.

- No features beyond what was asked. No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you wrote 200 lines and it could be 50, rewrite it. Ask: "would a senior
  engineer call this overcomplicated?" If yes, simplify.

### Surgical changes — touch only what you must

- Don't "improve" adjacent code, comments, or formatting; don't refactor what
  isn't broken; match the existing style even if you'd do it differently.
- Notice unrelated dead code → mention it, don't delete it.
- Remove imports/vars/functions *your* change orphaned; leave pre-existing dead
  code unless asked.
- The test: every changed line traces directly to the request.

### Goal-driven execution — define success, loop until verified

- Turn the task into a verifiable goal: "add validation" → "write tests for
  invalid inputs, then make them pass"; "fix the bug" → "write a failing repro
  test, then make it pass". Weak criteria ("make it work") force constant
  re-clarification; strong criteria let you loop independently.
- For multi-step work, state a brief plan with a `verify:` check per step.
- **Convergence loops need a quality bar, not a round count.** Before any
  iterate-and-narrow loop (names, designs, copy, options), state the rubric a
  winning candidate must meet and score against it. Fold the user's stated
  reasons into the rubric; don't re-ask the same judgment each round.
- **Build the load-bearing artifact first.** When artifacts depend on each other,
  name the dependency order (structure before title, schema before queries, API
  before UI) and build the spine first — don't let the easy artifact eat the
  session while the load-bearing one stays unbuilt.

Working if: fewer unnecessary diff lines, fewer rewrites from overcomplication,
and clarifying questions arriving before implementation rather than after.

## Accuracy

- Never guess at unknown APIs, libraries, or conventions — look them up. A
  plausible-but-wrong signature wastes more time than the lookup. Point at the
  source of truth (the actual docs, the actual file), don't paraphrase from
  memory.
- If a path doesn't exist, check for similar paths and suggest them rather than
  inventing one.
- If the setup provides a Docker image, prefer using it over reconstructing the
  environment.
- If the spec is ambiguous, stop and ask — don't assume. A wrong assumption
  compounds through everything built on it.
- Verify before declaring done. Run the test, read the actual diff, check the
  output. Self-verification is the highest-leverage habit in agentic coding —
  an unverified "done" is just a guess.

## Adversarial review at milestones

At a meaningful milestone — phase complete, feature green, before merging — run
an adversarial review before declaring done. A fresh adversarial pass catches
what the author's eye glides over.

- Launch via the Codex companion script:
  `node ${CLAUDE_PLUGIN_ROOT_FOR_CODEX}/scripts/codex-companion.mjs adversarial-review --background --base <ref> "<focus>"`.
  The `/codex:adversarial-review` slash command is `disable-model-invocation: true`;
  calling the companion script directly via Bash is the supported path.
- Allow-list the companion script in the project's `.claude/settings.local.json`
  once per repo first.
- Run inside the topic's worktree with `--base main` (or the parent ref) so the
  review sees only your diff, not unrelated dirty files.
- For larger diffs, spawn two parallel reviews with disjoint focus prompts; each
  prompt explicitly tells the reviewer to ignore the other's slice.
- Fix only in-scope blockers. Log out-of-scope findings to `KNOWN_ISSUES.md`
  rather than expanding scope.
- Re-run reviewers after fixes until no blockers remain, then merge.

## Delegating implementation to Codex

Delegate non-trivial implementation to the `codex:codex-rescue` subagent.
Reserve direct in-thread implementation for trivial edits.

- **Default model**: strongest available (`gpt-5.4` / `codex-high` equivalent)
  with max reasoning effort, unless the task is trivial.
- **Non-trivial** (delegate): multi-file changes, anything needing design
  judgment, refactors, bug investigation, anything a fresh review would improve,
  anything beyond ~10 minutes of in-thread work.
- **Trivial** (stay in-thread): orientation reads, known-path edits with no
  logic, mechanical search-and-replace, formatting, single-file fixes already
  fully scoped by the user.
- **Brief narrowly**: exact files, exact behavior change, the test/evidence for
  done, no scope creep.
- **Trust but verify**: always read the actual diff Codex produced before marking
  work done — never rely on its summary alone.
