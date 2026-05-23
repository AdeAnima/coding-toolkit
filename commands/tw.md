---
description: Explicit `/tw <init|new|next|status|link|check>` invocation of the task-workflow PM helper. Only for a literally typed /tw command — NOT for natural-language questions about what to build or work on next; those route to the task-workflow skill.
argument-hint: "[init | new <kind> \"title\" … | next | status <id> <status> | link <id> spec|plan <path> | check]"
---

Run the task-workflow helper with the arguments the user passed.

The script is at `${CLAUDE_PLUGIN_ROOT}/skills/task-workflow/scripts/tw.sh` and
operates on the `pm/` vault in the current git repo. Execute it via Bash:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/task-workflow/scripts/tw.sh" $ARGUMENTS
```

If `$ARGUMENTS` is empty, show the usage by running the script with no args.

Preflight: do NOT hand-check `pm/` or scan for trackers yourself — run the
script and let its exit code gate you. On a non-zero exit the script prints
either a migration HALT directive (repo has a foreign tracker, no vault) or
`tw: run 'tw.sh init' first` (no vault, no tracker). Obey whichever it prints,
exactly as the `task-workflow` skill's preflight section describes. Never
improvise a backlog by reading a tracker yourself.

After a `status`/`link`/`new`, run `tw.sh check` if a bulk change was made so
malformed frontmatter doesn't silently break the Bases views. For the full
workflow and the PM-task-vs-plan-step distinction, consult the `task-workflow`
skill.
