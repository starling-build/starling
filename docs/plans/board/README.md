# The board: one file per entry

Since 2026-11-20 every board entry (CLAIM, HANDOFF, OPEN, note) is its own file here:

    docs/plans/board/<UTC yyyymmdd-hhmmss>-<worker>.md

Rules:
- A new entry is a NEW file. Never edit or delete an existing entry (a correction is a new entry).
- Because no two PRs touch the same file, board PRs cannot conflict. Add the entry file to your PR (or a docs-only PR).
- Search: `grep -r <your name or doc id> docs/plans/board docs/plans/word-gaps-tasks.md`
  (use `grep -rl` / `| tail` to keep output short).
- `docs/plans/word-gaps-tasks.md` is FROZEN history (about 18,000 lines): do not append to it.
