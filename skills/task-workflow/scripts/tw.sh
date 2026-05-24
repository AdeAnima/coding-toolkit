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
#   tw.sh rename-files   # repair task filenames to T-NNN-<slug>.md from frontmatter

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
tw: STOP. No pm/ vault, but this repo already tracks work in '$tracker'.

    The user's question is now PAUSED. Do not answer it yet. Do not read
    '$tracker' or any other tracker to assemble a backlog yourself — that is the
    exact freelancing this gate exists to stop.

    Your one allowed next action: ask the user this single question and wait.

      "This repo tracks work in '$tracker' but has no task-workflow vault.
       Migrate it into a pm/ vault now, or answer just this once from the
       tracker without setting one up?"

    - Migrate  -> load the 'task-workflow' skill, follow its "Migrating an
                  existing tracker" branch (ask control level, 'tw.sh init',
                  dispatch the migration sub-agent), THEN answer.
    - Just this once -> only then may you read the tracker to answer, and tell
                  the user how to migrate later.

    Until the user picks, take no other action.
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
    # Filenames are T-NNN-<slug>.md (or legacy T-NNN.md); take the digit run
    # before the first dash so the slug never pollutes the number.
    n="${n%%-*}"
    # 10# forces base-10: zero-padded ids like 008/009 are otherwise read as
    # octal and crash arithmetic ("value too great for base").
    [ "$((10#$n))" -gt "$((10#$max))" ] 2>/dev/null && max="${n}"
  done
  # max may carry leading zeros (e.g. "008"); normalise to base-10 for printf.
  printf 'T-%03d' "$((10#$max + 1))"
}

# Vendored community plugin that gives the vault a real kanban board (native
# Bases has no kanban view). MIT, frozen at the version in templates/vendor.
KANBAN_PLUGIN_ID="kanban-bases-view"

# Copy the vendored kanban plugin into the vault and enable it. Idempotent:
# refreshes the plugin files (cp overwrites) and merges the id into
# community-plugins.json without duplicating it. Skipped silently if the vendor
# dir is absent so a stripped-down checkout still inits a working vault.
install_kanban_plugin() {
  local v="$1" src dst
  src="$(dir_template)/vendor/$KANBAN_PLUGIN_ID"
  [ -d "$src" ] || { printf 'note: kanban plugin not vendored; skipping (board falls back to table view)\n'; return 0; }
  dst="$v/.obsidian/plugins/$KANBAN_PLUGIN_ID"
  mkdir -p "$dst"
  cp "$src/main.js" "$src/manifest.json" "$src/styles.css" "$dst/"
  [ -e "$src/LICENSE" ] && cp "$src/LICENSE" "$dst/"

  # Enable: community-plugins.json is a JSON array of enabled plugin ids.
  local cpf="$v/.obsidian/community-plugins.json"
  if [ -e "$cpf" ] && command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg id "$KANBAN_PLUGIN_ID" '(. + [$id]) | unique' "$cpf" >"$tmp" 2>/dev/null \
      && mv "$tmp" "$cpf" || { printf '["%s"]\n' "$KANBAN_PLUGIN_ID" >"$cpf"; rm -f "$tmp"; }
  else
    printf '["%s"]\n' "$KANBAN_PLUGIN_ID" >"$cpf"
  fi
}

# Copy a scaffold file only if absent. NOT `cp -n`: BSD/macOS `cp -n` exits 1
# when the destination exists, which trips `set -e` and aborts a re-init over an
# existing vault — so init was never idempotent on macOS. A pre-check copy keeps
# init safe to re-run (the whole point) and never clobbers a user-edited base.
copy_if_absent() {
  [ -e "$2" ] || cp "$1" "$2"
}

cmd_init() {
  local v; v="$(vault)"
  mkdir -p "$v"/{tasks,epics,milestones,archive}
  copy_if_absent "$(dir_template)/board.base"        "$v/board.base"
  copy_if_absent "$(dir_template)/backlog.base"      "$v/backlog.base"
  copy_if_absent "$(dir_template)/by-epic.base"      "$v/by-epic.base"
  copy_if_absent "$(dir_template)/by-milestone.base" "$v/by-milestone.base"
  # Minimal vault marker so Obsidian recognises it; keep config out of git noise.
  mkdir -p "$v/.obsidian"
  install_kanban_plugin "$v"
  printf 'pm vault initialised at %s\n' "$v"
  printf 'Kanban board enabled via vendored %s plugin.\n' "$KANBAN_PLUGIN_ID"
  printf 'Add to .gitignore: pm/.obsidian/workspace*  pm/.obsidian/cache\n'
  printf 'First Obsidian open shows "trust the authors of this vault?" — click Trust so the board loads.\n'
}

# Rename task files to the descriptive T-NNN-<slug>.md form from their own
# frontmatter (id + title). Idempotent: a file already at its target name is left
# alone; a target occupied by a *different* note is reported, not clobbered; a
# target that is a byte-identical duplicate of the source is collapsed. Safe to
# run repeatedly — this is the repair path for an ambiguous-id vault.
cmd_rename_files() {
  require_vault
  local v changed=0 conflict=0 f id title slug target
  v="$(vault)"
  for f in "$v"/tasks/*.md; do
    [ -e "$f" ] || continue
    id="$(fm_get "$f" id)"; title="$(fm_get "$f" title)"
    [ -n "$id" ] || { printf 'skip (no id): %s\n' "${f##*/}"; continue; }
    slug="$(slugify "$title")"
    target="$v/tasks/$id${slug:+-$slug}.md"
    [ "$f" = "$target" ] && continue
    if [ -e "$target" ]; then
      if cmp -s "$f" "$target"; then
        rm -f "$f"; printf 'dedup: removed duplicate %s (kept %s)\n' "${f##*/}" "${target##*/}"; changed=1
      else
        printf 'CONFLICT: %s -> %s already exists with different content\n' "${f##*/}" "${target##*/}"; conflict=1
      fi
      continue
    fi
    mv "$f" "$target"; printf 'renamed: %s -> %s\n' "${f##*/}" "${target##*/}"; changed=1
  done
  [ "$changed" -eq 0 ] && [ "$conflict" -eq 0 ] && echo "rename-files: nothing to do"
  return "$conflict"
}

# Derive a vault-safe slug from a title: lowercase, every run of non-alphanumeric
# chars becomes a single dash, leading/trailing dashes trimmed. Fallback only —
# callers that need a specific id (e.g. migration, where task notes reference an
# epic by a chosen short slug) should pass --slug to pin it instead of relying on
# this derivation, which cannot reproduce an abbreviation of the title.
slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'
}

# parse --flag value pairs after the positional title
parse_flags() {
  EPIC=""; MILESTONE=""; PRIORITY="2"; DUE=""; SLUG=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --epic) EPIC="$2"; shift 2 ;;
      --milestone) MILESTONE="$2"; shift 2 ;;
      --priority) PRIORITY="$2"; shift 2 ;;
      --due) DUE="$2"; shift 2 ;;
      --slug) SLUG="$2"; shift 2 ;;
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
      [ -n "$SLUG" ] && die "new task: --slug not allowed (task ids are auto-assigned T-NNN)"
      local id; id="$(next_task_id)"
      # Descriptive filename: T-NNN-<slug>.md. The id stays the lookup key
      # (parsed back out by next_task_id / task_file); the slug is for humans
      # reading a folder listing. Empty title -> bare id (slug would be empty).
      local tslug; tslug="$(slugify "$title")"
      local f="$v/tasks/$id${tslug:+-$tslug}.md"
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
      # --slug pins the full id verbatim (what task --epic references); the guard
      # rejects a slug missing the epic- prefix so typos fail loud. Otherwise
      # derive the full id from the title.
      local slug
      if [ -n "$SLUG" ]; then
        case "$SLUG" in
          epic-*) slug="$SLUG" ;;
          *) die "new epic: --slug must start with 'epic-' (got '$SLUG')" ;;
        esac
      else
        slug="epic-$(slugify "$title")"
      fi
      local f="$v/epics/$slug.md"
      sed -e "s|^id:.*|id: $slug|" \
          -e "s|^title:.*|title: $title|" \
          -e "s|^milestone:.*|milestone: \"[[${MILESTONE:-}]]\"|" \
          -e "s|^created:.*|created: $(today)|" \
          -e "s|^# <epic title>|# $title|" \
          -e "s|\\[\\[epic-<slug>\\]\\]|[[$slug]]|g" \
          "$(dir_template)/epic.md" >"$f"
      scrub_fm_comments "$f"
      printf '%s  %s\n' "$slug" "$f" ;;
    milestone)
      local slug
      if [ -n "$SLUG" ]; then
        case "$SLUG" in
          m-*) slug="$SLUG" ;;
          *) die "new milestone: --slug must start with 'm-' (got '$SLUG')" ;;
        esac
      else
        slug="m-$(slugify "$title")"
      fi
      local f="$v/milestones/$slug.md"
      sed -e "s|^id:.*|id: $slug|" \
          -e "s|^title:.*|title: $title|" \
          -e "s|^due:.*|due: ${DUE:-}|" \
          -e "s|^created:.*|created: $(today)|" \
          -e "s|^# <milestone title>|# $title|" \
          "$(dir_template)/milestone.md" >"$f"
      scrub_fm_comments "$f"
      printf '%s  %s\n' "$slug" "$f" ;;
    *) die "new: kind must be task|epic|milestone" ;;
  esac
}

# Resolve a task id (T-NNN) to its file. Filenames are T-NNN-<slug>.md, so look
# up by id prefix across tasks/ then archive/. Matches both the descriptive form
# and the legacy bare T-NNN.md. More than one match for an id is a corrupt vault
# (e.g. a stale slug left beside a renamed one) — error loudly rather than guess.
task_file() {
  require_vault
  local id="$1" v; v="$(vault)"
  local d m matches
  for d in tasks archive; do
    matches=()
    for m in "$v/$d/$id.md" "$v/$d/$id"-*.md; do
      [ -e "$m" ] && matches+=("$m")
    done
    case "${#matches[@]}" in
      0) continue ;;
      1) printf '%s' "${matches[0]}"; return 0 ;;
      *) die "ambiguous id $id: ${#matches[@]} files match in $d/ (${matches[*]##*/}). Run 'tw.sh rename-files' to fix." ;;
    esac
  done
  die "no such task: $id"
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
  [ $# -ge 1 ] || die "usage: tw.sh {init|new|next|status|link|check|rename-files} …"
  local cmd="$1"; shift
  case "$cmd" in
    init) cmd_init ;;
    new) cmd_new "$@" ;;
    next) cmd_next ;;
    status) [ $# -eq 2 ] || die "usage: tw.sh status <id> <status>"; cmd_status "$@" ;;
    link) [ $# -eq 3 ] || die "usage: tw.sh link <id> spec|plan <path>"; cmd_link "$@" ;;
    check) cmd_check ;;
    rename-files) cmd_rename_files ;;
    *) die "unknown command: $cmd" ;;
  esac
}

main "$@"
