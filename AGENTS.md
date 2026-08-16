# school-app

Teacher-owned tests app: students have no accounts and enter via unique `/t/:token` links. Rails 8,
Hotwire, Minitest, SQLite, Ukrainian UI.

## The rules are in `docs/agent-rules.md`

Read it before your first edit in a session. It is the single source of truth for domain naming, style,
security, the attempt-lifecycle invariants, quality, git, and when to ask.

This file adds nothing of its own. If it and `docs/agent-rules.md` ever disagree, `docs/agent-rules.md`
wins — and the disagreement is a bug in this file.

Other entry points, all pointing at the same rules: `CLAUDE.md` (Claude Code),
`.cursor/rules/conventions.mdc` (Cursor).

Note for maintainers: some global gitignores exclude `/AGENTS.md`, so `.gitignore` negates it explicitly.
If it ever goes untracked, `git add -f AGENTS.md`.
