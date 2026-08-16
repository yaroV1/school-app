# school-app — Claude Code

## The rules are in `docs/agent-rules.md`

Read it before your first edit in a session. Single source of truth for domain naming, style, security,
the attempt-lifecycle invariants, quality, git, and when to ask. If this file and `docs/agent-rules.md`
disagree, `docs/agent-rules.md` wins.

This file adds Claude-only mechanics and nothing else.

## Skills

- `/prd` — reach for it when `docs/agent-rules.md` § When to ask vs inspect says to; that clause, ending
  "None of those: just do it", is the trigger. Contract: `.claude/skills/prd/SKILL.md`.
- `/implement-prd` — executes a PRD already in `prd/backlog/`. Contract:
  `.claude/skills/implement-prd/SKILL.md`; the git carve-out it runs under is `docs/agent-rules.md` § Git,
  scoped by that skill's § Git authorization.

Stage lifecycle for `prd/`: `prd/README.md`.

## Enforcement

`.claude/settings.json` (ask/deny) and the PreToolUse hook `.claude/hooks/git-guard.rb` mechanically
enforce `docs/agent-rules.md` § Git. A blocked git command means you hit a rule in that section, not a
tooling bug. Read the rule rather than working around the block.
