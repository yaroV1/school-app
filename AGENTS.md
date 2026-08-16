# school-app

Teacher-owned tests app; students have no accounts and enter via unique `/t/:token` links.

## Read `docs/agent-rules.md` first

Open it before your first edit in this session, not after. It is the single source of truth for domain
naming, style, security, the attempt-lifecycle invariants, quality, git, and when to ask.

This file adds nothing of its own. If it and `docs/agent-rules.md` ever disagree, `docs/agent-rules.md`
wins — and the disagreement is a bug in this file.

This repo does not expose the Claude-native `/prd` and `/implement-prd` workflows as Codex skills. Do not
reconstruct them by hand; they run only where available and when the developer invokes them. Codex has no
project git guard for the absolutes in that file; they bind you anyway.
