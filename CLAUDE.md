# school-app — Claude Code

## The rules are in `docs/agent-rules.md`

Read it before your first edit in a session. Single source of truth for domain naming, style, security,
the attempt-lifecycle invariants, quality, git, and when to ask. If this file and `docs/agent-rules.md`
disagree, `docs/agent-rules.md` wins.

This file adds Claude-only mechanics and nothing else.

## Skills

Both run **only when the developer invokes them** — the slash command, or asking for it in their own words.
Never start either on your own initiative, however large or risky the change looks. When
`docs/agent-rules.md` § When to ask vs inspect says to stop and ask, ask; naming a PRD as an option is
allowed, starting one is not.

- `/prd` — writes a local, git-ignored spec into `prd/<name>/`. Contract:
  `.claude/skills/prd/SKILL.md`.
- `/implement-prd` — executes a PRD from `prd/<name>/`. Contract:
  `.claude/skills/implement-prd/SKILL.md`; the git carve-out it runs under is `docs/agent-rules.md` § Git,
  scoped by that skill's § Git authorization.

## Git guard

`.claude/settings.json` (ask/deny) and the PreToolUse hook `.claude/hooks/git-guard.rb` block common
forbidden forms from `docs/agent-rules.md` § Git. The hook is best-effort, not a shell parser; the written
rules remain authoritative. A blocked git command means you hit a rule in that section, not a tooling bug.
Read the rule rather than working around the block.
