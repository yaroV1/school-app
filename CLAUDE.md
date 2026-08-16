# school-app — Claude Code

## The rules are in `docs/agent-rules.md`

Read it before your first edit in a session. Single source of truth for domain naming, style, security,
the attempt-lifecycle invariants, quality, git, and when to ask. If this file and `docs/agent-rules.md`
disagree, `docs/agent-rules.md` wins.

This file adds Claude-only mechanics and nothing else.

## Skills

- `/prd` — writes `prd/_to_refine/<name>/project.md`. Writes no code, commits nothing. The trigger list is
  the skill's own description; the short version is: run it before code when the change is bigger than one
  commit. See `docs/agent-rules.md` § When to ask vs inspect.
- `/implement-prd` — executes a PRD already in `prd/backlog/`, one task per commit, with a review fan-out
  before each commit. It refuses `prd/_to_refine/`. It commits under the carve-out in
  `docs/agent-rules.md` § Git; scope and limits are in `.claude/skills/implement-prd/SKILL.md`
  § Git authorization.

Stage lifecycle for `prd/`: `prd/README.md`.

## Enforcement

`.claude/settings.json` (ask/deny) and the PreToolUse hook `.claude/hooks/git-guard.rb` mechanically
enforce `docs/agent-rules.md` § Git. A blocked git command means you hit a rule in that section, not a
tooling bug. Read the rule rather than working around the block.
