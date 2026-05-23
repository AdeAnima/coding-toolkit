---
description: Run the task-workflow PM helper (init/new/next/status/link/check) on the current repo's pm/ vault.
argument-hint: "[init | new <kind> \"title\" … | next | status <id> <status> | link <id> spec|plan <path> | check]"
---

Run the task-workflow helper with the arguments the user passed.

The script is at `${CLAUDE_PLUGIN_ROOT}/skills/task-workflow/scripts/tw.sh` and
operates on the `pm/` vault in the current git repo. Execute it via Bash:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/task-workflow/scripts/tw.sh" $ARGUMENTS
```

If `$ARGUMENTS` is empty, show the usage by running the script with no args.
After a `status`/`link`/`new`, run `tw.sh check` if a bulk change was made so
malformed frontmatter doesn't silently break the Bases views. For the full
workflow and the PM-task-vs-plan-step distinction, consult the `task-workflow`
skill.
