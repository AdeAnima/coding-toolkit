---
id: epic-<slug>
title: <epic title>
status: open           # open|done|cancelled
milestone: "[[m-<slug>]]"
created: YYYY-MM-DD
---

# <epic title>

## Goal
<the outcome this epic delivers — narrative, not a task list>

## Scope
<what's in / out>

## Tasks

Tasks belong to this epic via their own `epic:` frontmatter — do not maintain a
list by hand. The embedded view rolls them up automatically.

```base
filters:
  and:
    - 'file.inFolder("tasks")'
    - 'note.epic == "[[epic-<slug>]]"'
views:
  - type: table
    name: Tasks in this epic
    order:
      - note.id
      - note.status
      - note.priority
      - file.name
```
