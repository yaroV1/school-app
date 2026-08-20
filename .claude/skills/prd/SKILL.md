---
name: prd
description: "Writes a concise local product requirements document for a school-app feature. Use only when the developer explicitly asks for a PRD, spec, feature plan, or scoping document. Produces git-ignored prd/<name>/project.md for /implement-prd."
---

# PRD

Turn a feature request into a concise, executable plan at `prd/<kebab-name>/project.md` before writing
code. The whole `prd/` directory is local and git-ignored.

`docs/agent-rules.md` is the canonical contract for domain naming, style, security, quality, and git.
Read it first and apply only the parts relevant to the feature.

## Invocation

- `/prd <feature description>` — research and write the PRD.
- `/prd` — ask what feature to plan, then continue.

Never start this workflow unless the developer asks for it. A request to implement a feature is not by
itself a request for a PRD.

## Workflow

1. **Clarify only what matters.** If the outcome or a hard-to-reverse product decision is unclear, ask up
   to three focused questions. Otherwise proceed from the request.
2. **Research the ownership path.** Read the existing controller, model/service, view, and tests that own
   the behavior. Read schema, routes, locales, jobs, or security boundaries only when the feature touches
   them. Use real paths and existing names; do not inventory unrelated parts of the app.
3. **Choose a kebab-case name.** Stop rather than overwrite an existing `prd/<name>/project.md`.
4. **Write the PRD** using the compact template below. Keep it proportional: a small feature should fit on
   about one page.
5. **Check it.** The user outcome is testable, named paths are real or marked new, tasks are ordered, and
   any relevant security or migration decision is explicit. Fix gaps instead of reporting them.
6. **Report** the path and task count. Do not stage, commit, push, or implement the PRD.

## What belongs in the PRD

Use existing code by default. Explain a new table, dependency, service, or client-side controller only
when the choice is not obvious; do not require a rejected-alternative essay for routine Rails objects.

Add a `## Constraints` section only for constraints that affect implementation, such as:

- student-facing fields and answer-key protection;
- teacher ownership scope or unauthenticated `Take::` access;
- assignment tokens, params, broadcasts, jobs, auth, or scoring;
- `AttemptLifecycle` concurrency;
- schema changes, backfills, or deployment compatibility;
- a product decision or explicit out-of-scope boundary.

Do not write six `N/A` security answers. When one of these risks applies, name the guard and the test that
proves it. Security rules remain mandatory even when the section is short.

Tasks are coherent vertical slices, not file-by-file steps. A task may include a model, controller, view,
locale, and test when they jointly deliver one behavior. Split only when slices are independently useful
or the suite cannot stay green. FR identifiers and requirement-to-task mapping are optional.

## Template

```markdown
# <Feature name>

## Goal

<Who needs what outcome, and why.>

## Acceptance Criteria

- <Observable, testable behavior.>
- <Observable failure, empty, or permission behavior when relevant.>

## Constraints

- <Only relevant domain, security, schema, or scope decisions. Omit this section if none.>

## Tasks

- [ ] <Coherent implementation slice> — proof: `test/...`
- [ ] <Next slice, if independently useful> — proof: `test/...`
```

Proof names the targeted test file or command that demonstrates the task. Optional work belongs outside
the task list. Blocking questions must be resolved before `/implement-prd` starts.
