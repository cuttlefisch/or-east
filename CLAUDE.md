# or-east

Org Roam Extended Attribute Stat Tracking — an Emacs minor mode that automatically tracks usage statistics on org-roam nodes.

## Structure

- `or-east-mode.el` — core package (time strings, body hashing, stat updates, hook management)
- `test/test-helper.el` — test fixtures, macros, org-roam stubs
- `test/test-or-east.el` — Buttercup test suite

## Dependencies

- `org-roam` (external, required — heavy dependency with SQLite)
- `org`, `org-id`, `ol`, `org-element` (built-in org modules)

## Key concepts

- Three tracked properties in node property drawers:
  - `last-accessed` — updated when node is opened via `org-roam-find-file`
  - `last-modified` — updated when body content changes (tracked via `buffer-hash`)
  - `last-linked` — updated when another node links to this one
- Hook-based architecture: `org-roam-find-file-hook`, `org-roam-post-node-insert-hook`, `after-save-hook`
- `or-east-node-stat-format-time-string` controls timestamp format (default `"%Y-%m-%d"`)

## Sorting integration pipeline

or-east integrates with org-roam's completion system to sort nodes by activity:

1. `org-roam-node-read` calls `org-roam-node-read--completions` to build candidates
2. It looks up `org-roam-node-default-sort` (set to `'activity`) and resolves to `org-roam-node-read-sort-by-activity` (a defalias for `or-east-node-sort-by-activity`)
3. Candidates are pre-sorted, then completion metadata sets `(display-sort-function . identity)` so vertico doesn't re-sort
4. `or-east-node-activity-score` computes a weighted, time-decayed score from `last-accessed`, `last-modified`, `last-linked` property drawer values
5. `or-east--parse-date` handles both ISO 8601 (`2026-03-21`) and legacy US (`03/21/26`) date formats

Key config: `~/.doom.d/config.el:455` sets `org-roam-node-default-sort` to `'activity`

## Development

- Emacs Lisp with `lexical-binding: t`
- Package requires Emacs 28.1+
- Tests: `make test` (uses Buttercup, 45 specs)
- Test runner auto-detects straight.el (Doom) or Cask
- Tests mock org-roam via Buttercup spies — no real database needed
