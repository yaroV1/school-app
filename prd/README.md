# PRD — three stages

    _to_refine/<kebab-name>/   project.md                 written by /prd, not yet reviewed
    backlog/<kebab-name>/      project.md + progress.md   reviewed, ready to build
    complete/<kebab-name>/     project.md + progress.md   shipped

`_to_refine → backlog` is a human move. No agent performs it.
`backlog → complete` is performed by `/implement-prd` at completion, and by nothing else.

`/prd <feature>` writes into `_to_refine/` only. Refine it, resolve its blocking Open Questions, move it to
`backlog/`.
`/implement-prd` works a `backlog/` entry, ticks its Implementation Tasks, keeps `progress.md`, and moves
the directory to `complete/` when every box is ticked.

Contracts: `.claude/skills/prd/SKILL.md`, `.claude/skills/implement-prd/SKILL.md`, and `docs/agent-rules.md`
(canonical).
