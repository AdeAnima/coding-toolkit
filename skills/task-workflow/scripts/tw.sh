#!/usr/bin/env bash
# task-workflow helper. Manages the PM vault at <repo>/pm.
#
# Frontmatter is read with grep/sed (no yq dependency) — the schema is flat and
# fixed, so a line-oriented reader is enough and keeps this portable. Writes go
# through the templates so types stay Bases-valid.
#
# Usage:
#   tw.sh init
#   tw.sh new task "Title" [--epic epic-slug] [--milestone m-slug] [--priority N]
#   tw.sh new epic "Title" [--milestone m-slug]
#   tw.sh new milestone "Title" [--due YYYY-MM-DD]
#   tw.sh next
#   tw.sh status T-042 in-progress
#   tw.sh link T-042 spec docs/superpowers/specs/2026-05-23-x-design.md
#   tw.sh link T-042 plan docs/superpowers/plans/2026-05-23-x.md
#   tw.sh check

set -euo pipefail

STATUSES="backlog speccing planning in-progress review done blocked cancelled"

die() { printf 'tw: %s\n' "$1" >&2; exit 1; }
today() { date +%Y-%m-%d; }

# Repo root, then vault root.
repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "not in a git repo"; }
vault() { printf '%s/pm' "$(repo_root)"; }

# Foreign trackers we recognise as "this repo already tracks work informally".
# A repo with one of these but no pm/ vault should be MIGRATED, not handed an
# empty vault — so the gate names the file and routes the agent to the skill.
FOREIGN_TRACKERS="project.md PROJECT.md ROADMAP.md TODO.md KNOWN_ISSUES.md BACKLOG.md TASKS.md"

# First foreign tracker present in the repo root, or empty string.
found_tracker() {
  local root t; root="$(repo_root)"
  for t in $FOREIGN_TRACKERS; do
    [ -e "$root/$t" ] && { printf '%s' "$t"; return 0; }
  done
  return 1
}

# Single missing-vault gate. Every non-init subcommand calls this so a missing
# vault always self-reports — never as "no such task" or "backlog empty". Probes
# pm/tasks (not bare pm/) so an unrelated or half-initialised pm/ dir doesn't
# pass as a real vault; init is idempotent, so the fix for a partial vault is
# always "run init".
#
# When the vault is missing AND a foreign tracker exists, the gate does NOT just
# say "run init" — it prints the migration directive INTO the tool output, at the
# decision point, and routes the agent to the task-workflow skill. This is
# deliberate: agents reliably obey a directive in fresh tool output but skip
# doctrine that merely lives behind a "see the skill" pointer. The script stays
# dumb (no migration logic, no control-level prompt) — it only gates and points.
require_vault() {
  [ -d "$(vault)/tasks" ] && return 0
  local tracker
  if tracker="$(found_tracker)"; then
    cat >&2 <<EOF
tw: no pm/ vault, but this repo already tracks work in '$tracker'.
    Do NOT improvise a backlog by reading trackers yourself. Load the
    'task-workflow' skill and follow its "Migrating an existing tracker" branch:
    ask the user's control level, run 'tw.sh init', then dispatch the migration
    sub-agent. If the user has declined migration (see the opt-out flag in the
    skill), run 'tw.sh init' to start an empty vault instead.
EOF
    exit 1
  fi
  die "run 'tw.sh init' first"
}

# Read a single frontmatter scalar: fm_get <file> <key>
# Strips an inline " # comment", surrounding whitespace, and quotes.
fm_get() {
  sed -n '/^---$/,/^---$/p' "$1" \
    | sed -n "s/^$2:[[:space:]]*//p" \
    | head -n1 \
    | sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
          -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}

# Set a frontmatter scalar in place: fm_set <file> <key> <value>
fm_set() {
  local f="$1" k="$2" v="$3" tmp
  tmp="$(mktemp)"
  awk -v k="$k" -v v="$v" '
    BEGIN { infm=0; done=0 }
    /^---$/ { fmcount++; print; next }
    fmcount==1 && done==0 && $0 ~ "^"k":" { print k": "v; done=1; next }
    { print }
  ' "$f" >"$tmp"
  mv "$tmp" "$f"
}

dir_template() { printf '%s/../templates' "$(dirname "$0")"; }

# Strip inline "# guidance" comments from frontmatter lines so stored values are
# clean for Bases. Operates only inside the first --- … --- block, in place.
scrub_fm_comments() {
  local f="$1" tmp; tmp="$(mktemp)"
  awk '
    /^---$/ { fmcount++; print; next }
    fmcount==1 { sub(/[[:space:]]*#.*$/, ""); print; next }
    { print }
  ' "$f" >"$tmp"
  mv "$tmp" "$f"
}

next_task_id() {
  local n max=0 id
  for f in "$(vault)"/tasks/T-*.md; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .md)"; n="${id#T-}"
    [ "$n" -gt "$max" ] 2>/dev/null && max="$n"
  done
  printf 'T-%03d' "$((max + 1))"
}

cmd_init() {
  local v; v="$(vault)"
  mkdir -p "$v"/{tasks,epics,milestones,archive}
  cp -n "$(dir_template)/board.base"   "$v/board.base"
  cp -n "$(dir_template)/backlog.base" "$v/backlog.base"
  # Minimal vault marker so Obsidian recognises it; keep config out of git noise.
  mkdir -p "$v/.obsidian"
  printf 'pm vault initialised at %s\n' "$v"
  printf 'Add to .gitignore: pm/.obsidian/workspace*  pm/.obsidian/cache\n'
}

# parse --flag value pairs after the positional title
parse_flags() {
  EPIC=""; MILESTONE=""; PRIORITY="2"; DUE=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) EPIC="$2"; shift 2 ;;
      --milestone) MILESTONE="$2"; shift 2 ;;
      --priority) PRIORITY="$2"; shift 2 ;;
      --due) DUE="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done
}

cmd_new() {
  local kind="$1" title="$2"; shift 2
  parse_flags "$@"
  require_vault; local v; v="$(vault)"
  case "$kind" in
    task)
      local id; id="$(next_task_id)"
      local f="$v/tasks/$id.md"
      sed -e "s|^id:.*|id: $id|" \
          -e "s|^title:.*|title: $title|" \
          -e "s|^epic:.*|epic: \"[[${EPIC:-}]]\"|" \
          -e "s|^milestone:.*|milestone: \"[[${MILESTONE:-}]]\"|" \
          -e "s|^priority:.*|priority: $PRIORITY|" \
          -e "s|^created:.*|created: $(today)|" \
          -e "s|^# <title>|# $title|" \
          "$(dir_template)/pm-task.md" >"$f"
      scrub_fm_comments "$f"
      printf '%s  %s\n' "$id" "$f" ;;
    epic)
      local slug; slug="$(printf '%s' "$title" | tr 'A-Z ' 'a-z-' )"
      local f="$v/epics/epic-$slug.md"
      sed -e "s|^id:.*|id: epic-$slug|" \
          -e "s|^title:.*|title: $title|" \
          -e "s|^milestone:.*|milestone: \"[[${MILESTONE:-}]]\"|" \
          -e "s|^created:.*|created: $(today)|" \
          -e "s|^# <epic title>|# $title|" \
          "$(dir_template)/epic.md" >"$f"
      scrub_fm_comments "$f"
      printf 'epic-%s  %s\n' "$slug" "$f" ;;
    milestone)
      local slug; slug="$(printf '%s' "$title" | tr 'A-Z ' 'a-z-' )"
      local f="$v/milestones/m-$slug.md"
      sed -e "s|^id:.*|id: m-$slug|" \
          -e "s|^title:.*|title: $title|" \
          -e "s|^due:.*|due: ${DUE:-}|" \
          -e "s|^created:.*|created: $(today)|" \
          -e "s|^# <milestone title>|# $title|" \
          "$(dir_template)/milestone.md" >"$f"
      scrub_fm_comments "$f"
      printf 'm-%s  %s\n' "$slug" "$f" ;;
    *) die "new: kind must be task|epic|milestone" ;;
  esac
}

task_file() {
  require_vault
  local id="$1" f="$(vault)/tasks/$id.md"
  [ -e "$f" ] || f="$(vault)/archive/$id.md"
  [ -e "$f" ] || die "no such task: $id"
  printf '%s' "$f"
}

cmd_next() {
  require_vault
  local best="" bestp=99 bestc="9999-99-99" id pr cr st f
  for f in "$(vault)"/tasks/T-*.md; do
    [ -e "$f" ] || continue
    st="$(fm_get "$f" status)"; [ "$st" = "backlog" ] || continue
    pr="$(fm_get "$f" priority)"; cr="$(fm_get "$f" created)"; id="$(fm_get "$f" id)"
    if [ "$pr" -lt "$bestp" ] 2>/dev/null || { [ "$pr" = "$bestp" ] && [[ "$cr" < "$bestc" ]]; }; then
      best="$f"; bestp="$pr"; bestc="$cr"
    fi
  done
  [ -n "$best" ] || { echo "backlog empty"; return 0; }
  printf '%s  P%s  %s  %s\n' "$(fm_get "$best" id)" "$bestp" "$(fm_get "$best" created)" "$(fm_get "$best" title)"
  printf '%s\n' "$best"
}

cmd_status() {
  local id="$1" new="$2" f; f="$(task_file "$id")"
  printf '%s' "$STATUSES" | grep -qw -- "$new" || die "bad status: $new (one of: $STATUSES)"
  fm_set "$f" status "$new"
  printf '%s -> %s\n' "$id" "$new"
}

cmd_link() {
  local id="$1" what="$2" path="$3" f; f="$(task_file "$id")"
  case "$what" in
    spec) fm_set "$f" spec_file "\"$path\"" ;;
    plan) fm_set "$f" plan_file "\"$path\"" ;;
    *) die "link: what must be spec|plan" ;;
  esac
  printf '%s %s_file = %s\n' "$id" "$what" "$path"
}

cmd_check() {
  local v fail=0 f st id known
  require_vault; v="$(vault)"
  for f in "$v"/tasks/*.md "$v"/archive/*.md; do
    [ -e "$f" ] || continue
    id="$(fm_get "$f" id)"; st="$(fm_get "$f" status)"
    [ -n "$id" ] || { echo "MISSING id: $f"; fail=1; }
    if [ -n "$st" ]; then
      printf '%s' "$STATUSES" | grep -qw -- "$st" || { echo "BAD status '$st': $f"; fail=1; }
    else
      echo "MISSING status: $f"; fail=1
    fi
  done
  # dangling epic/milestone wikilinks
  for f in "$v"/tasks/*.md; do
    [ -e "$f" ] || continue
    local e m
    e="$(fm_get "$f" epic | sed -e 's/\[\[//' -e 's/\]\]//')"
    m="$(fm_get "$f" milestone | sed -e 's/\[\[//' -e 's/\]\]//')"
    [ -z "$e" ] || [ -e "$v/epics/$e.md" ] || { echo "DANGLING epic '$e': $f"; fail=1; }
    [ -z "$m" ] || [ -e "$v/milestones/$m.md" ] || { echo "DANGLING milestone '$m': $f"; fail=1; }
  done
  [ "$fail" -eq 0 ] && echo "check: ok"
  return "$fail"
}

main() {
  [ $# -ge 1 ] || die "usage: tw.sh {init|new|next|status|link|check} …"
  local cmd="$1"; shift
  case "$cmd" in
    init) cmd_init ;;
    new) cmd_new "$@" ;;
    next) cmd_next ;;
    status) [ $# -eq 2 ] || die "usage: tw.sh status <id> <status>"; cmd_status "$@" ;;
    link) [ $# -eq 3 ] || die "usage: tw.sh link <id> spec|plan <path>"; cmd_link "$@" ;;
    check) cmd_check ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
