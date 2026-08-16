# school-app

Teacher-owned tests app; students have no accounts and enter via unique `/t/:token` links.

## Read `docs/agent-rules.md` first

Open it before your first edit in this session, not after. It is the single source of truth for domain
naming, style, security, the attempt-lifecycle invariants, quality, git, and when to ask.

This file adds nothing of its own. If it and `docs/agent-rules.md` ever disagree, `docs/agent-rules.md`
wins — and the disagreement is a bug in this file.

`/prd` and `/implement-prd` are Claude Code skills and do not exist here. Nothing in the rules asks you to
start one anyway — they run only when the developer invokes them. The git absolutes in that file have no
mechanical backstop outside Claude Code; they bind you anyway.
