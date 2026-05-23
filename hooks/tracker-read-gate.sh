#!/usr/bin/env bash
# coding-toolkit: BLOCKING PreToolUse gate for tracker reads pre-migration.
#
# The task-workflow skill owns detection/ranking/migration of an informal
# tracker (project.md, ROADMAP.md, …) into a pm/ vault. But agents bypass the
# skill PRE-EMPTIVELY: they reflexively read the tracker to orient before ever
# running skill-selection, so no description lever can catch them. This hook is
# the deterministic backstop — it intercepts the read itself and routes it.
#
# Fires only when ALL hold:
#   - the read targets a known tracker basename AT THE REPO ROOT
#   - the repo has NO pm/ vault (once `tw init` runs, pm/ exists -> silent, so
#     the legitimate migration sub-agent dispatched after init is never blocked)
#   - the repo carries a .claude/ marker (an agent-driven project, not noise)
# Override: include "# allow-tracker-read" anywhere in the same tool input.
#
# Covers both Read tool and Bash file-readers (cat/head/tail/less/more/bat),
# because the observed bypass used `head -100 KNOWN_ISSUES.md` etc.
#
# Blocks via PreToolUse permissionDecision=deny (exits 0 with JSON). Fails open
# (silent exit 0) on any ambiguity — a missed block is a nudge lost, a false
# block is the user stuck.

set -euo pipefail

input="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty')"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')"

# Tracker basenames the skill claims ownership of.
trackers='project.md ROADMAP.md TODO.md KNOWN_ISSUES.md BACKLOG.md TASKS.md'

# --- Extract candidate target paths + an override-scan blob, per tool. ---
override_blob=""
declare -a candidates=()

case "$tool_name" in
  Read)
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    [ -n "$fp" ] || exit 0
    candidates+=("$fp")
    override_blob="$fp"
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    [ -n "$cmd" ] || exit 0
    override_blob="$cmd"
    # Only inspect commands that read file contents to stdout.
    printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(cat|head|tail|less|more|bat)([[:space:]]|$)' || exit 0
    # Pull every token that ends in a known tracker basename.
    for t in $trackers; do
      while IFS= read -r tok; do
        [ -n "$tok" ] && candidates+=("$tok")
      done < <(printf '%s' "$cmd" | grep -oE "[^[:space:]\"'\`|;&)(]*${t}\b" || true)
    done
    ;;
  *)
    exit 0
    ;;
esac

[ "${#candidates[@]}" -gt 0 ] || exit 0

# Explicit override -> stay silent.
case "$override_blob" in
  *"# allow-tracker-read"*) exit 0 ;;
esac

# --- Resolve repo root from cwd; require it to be a git repo with a marker. ---
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0
repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo_root" ] || exit 0

# Positive marker: an agent-driven project. No marker -> not our concern.
[ -d "$repo_root/.claude" ] || exit 0

# Migration already done (or in progress) -> vault exists -> never block.
[ -d "$repo_root/pm" ] && exit 0

# --- Does any candidate resolve to a tracker AT the repo root? ---
hit=""
for c in "${candidates[@]}"; do
  base="$(basename "$c")"
  match=""
  for t in $trackers; do
    [ "$base" = "$t" ] && match="$t" && break
  done
  [ -n "$match" ] || continue

  # Confirm it sits AT the repo root, not nested. Resolve both the candidate's
  # parent dir and the repo root with `pwd -P` so symlinked paths (e.g. /tmp ->
  # /private/tmp on macOS, or a symlinked home) compare equal.
  case "$c" in
    /*) parent="$(dirname "$c")" ;;
    *)  parent="$repo_root" ;;   # relative read is resolved from repo root
  esac
  [ -d "$parent" ] || continue
  parent_real="$(cd "$parent" 2>/dev/null && pwd -P)" || continue
  root_real="$(cd "$repo_root" 2>/dev/null && pwd -P)" || continue
  if [ "$parent_real" = "$root_real" ] && [ -f "$root_real/$base" ]; then
    hit="$base"
    break
  fi
done

[ -n "$hit" ] || exit 0

reason="About to read the tracker '${hit}' but this repo has no pm/ vault. Do not orient by reading trackers yourself — invoke Skill(coding-toolkit:task-workflow). It owns detection, ranking, and migrating the tracker into a pm/ vault. If this read is genuinely intentional (e.g. reviewing the file's content, not building a backlog), re-issue the exact same command with '# allow-tracker-read' appended."

jq -nc --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'

exit 0
