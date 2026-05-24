# Vendored Obsidian community plugins

These are third-party plugins bundled so `tw init` can give a PM vault a real
board without a network round-trip. They are copied verbatim into
`pm/.obsidian/plugins/<id>/` and enabled via `pm/.obsidian/community-plugins.json`.

## kanban-bases-view

- **Source:** https://github.com/xiwcx/obsidian-bases-kanban
- **License:** MIT (see `kanban-bases-view/LICENSE`) — redistribution permitted
  with the license retained, which is why `LICENSE` ships alongside the assets.
- **Vendored version:** 0.10.0 (view type `kanban-view`, config keys
  `groupByProperty` / `swimlaneByProperty` / `cardTitleProperty`).
- **Why vendored, not downloaded at init:** deterministic, offline, no network
  dependency in the migration path.

### Upgrading

The files freeze at the vendored version. To upgrade, re-download the release
assets into `kanban-bases-view/` and refresh `LICENSE` if it changed:

```sh
ver=0.11.0   # desired release tag
base="https://github.com/xiwcx/obsidian-bases-kanban/releases/download/$ver"
for f in main.js manifest.json styles.css; do
  curl -sL -o "kanban-bases-view/$f" "$base/$f"
done
curl -sL -o kanban-bases-view/LICENSE \
  https://raw.githubusercontent.com/xiwcx/obsidian-bases-kanban/main/LICENSE
```

Then bump the plugin version and verify the view type / config keys still match
what `templates/*.base` emit (they changed between early releases).

> Long term this dependency is meant to be replaced by a first-party Bases
> renderer — see PROJECT.md "Own Bases display".
