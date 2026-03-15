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
- `or-east-node-stat-format-time-string` controls timestamp format (default `"%D"`)

## Development

- Emacs Lisp with `lexical-binding: t`
- Package requires Emacs 28.1+
- Tests: `make test` (uses Buttercup, 16 specs)
- Test runner auto-detects straight.el (Doom) or Cask
- Tests mock org-roam via Buttercup spies — no real database needed
