#!/usr/bin/env bash
# coding-toolkit: warn-only PreToolUse gate for Edit/Write.
#
# Nudges code edits into an isolated git worktree. We warn even on a feature
# branch in the MAIN checkout, because multiple agents may share that branch and
# a topic checkout there mixes or destroys their working-tree state. A LINKED
# worktree is the safe place, so we stay silent there. Non-git dirs are silent.
#
# Non-blocking: always exits 0. It injects advisory context, never denies.
# Fires at most once per session to avoid rule fatigue.

set -euo pipefail

input="$(cat)"

# jq is the documented way to read hook stdin. If absent, fail open (silent).
command -v jq >/dev/null 2>&1 || exit 0

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "nosession"')"

# Decide which directory to evaluate: the target file's dir if we have an
# absolute path, otherwise the session cwd.
target_dir=""
if [ -n "$file_path" ] && [ "${file_path#/}" != "$file_path" ]; then
  target_dir="$(dirname "$file_path")"
elif [ -n "$cwd" ]; then
  target_dir="$cwd"
else
  exit 0
fi
[ -d "$target_dir" ] || target_dir="$cwd"
[ -d "$target_dir" ] || exit 0

# Not a git repo -> nothing to gate.
git_dir="$(git -C "$target_dir" rev-parse --git-dir 2>/dev/null || true)"
[ -n "$git_dir" ] || exit 0

# Inside a linked worktree -> already isolated, stay silent.
case "$git_dir" in
  */worktrees/*) exit 0 ;;
esac

# Warn once per session.
marker="${TMPDIR:-/tmp}/coding-toolkit-wt-${session_id}"
[ -e "$marker" ] && exit 0
: > "$marker" 2>/dev/null || true

branch="$(git -C "$target_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

read -r -d '' msg <<EOF || true
coding-toolkit: editing in the MAIN working tree of a git repo (branch: ${branch}), not an isolated worktree. Other agents may share this checkout — a topic branch or dirty tree here can mix with or destroy their work. Before edits beyond a 1-line fix, move to an isolated worktree: prefer the EnterWorktree tool, else 'git worktree add'. Run 'git worktree list' first to avoid duplicating one. After entering a NEW worktree, immediately call '/rename <worktree-basename>'. This is a one-time per-session reminder; proceed if a worktree is unwarranted (trivial fix, non-collaborative repo).
EOF

jq -nc --arg ctx "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: $ctx
  }
}'

exit 0
