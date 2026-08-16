---
name: implement-prd
description: Execute a refined PRD from prd/backlog/ one task at a time — implement, test, review by parallel subagents, fix, then commit. Use when the user says /implement-prd, asks to build, ship, implement, continue, or resume a PRD or a named feature that already has a PRD, or asks for the next task in one. Not for one-off changes that need no PRD; § Invocation refuses PRDs still in prd/_to_refine/.
---

# Implement PRD

Execute `prd/backlog/<name>/project.md`: one task, one review round, one commit — repeated until the
task list is empty.

`docs/agent-rules.md` is the canonical contract for naming, style, security, quality, and git. This skill does not
restate those rules; it sequences the work and says when each check runs. If this file and `docs/agent-rules.md`
disagree, `docs/agent-rules.md` wins.

## Invocation

- `/implement-prd <feature-name>` — a directory under `prd/backlog/`.
- `/implement-prd` — list `prd/backlog/*/` and ask which one. Do not guess. If the directory is absent
  or holds nothing but `.keep`, say the backlog is empty and stop. Do not create an entry.
- `prd/_to_refine/<name>/` is refused. Unrefined by definition: blocking Open Questions may still be
  open and the task list is not a contract yet. Tell the user to refine it and move it to
  `prd/backlog/`. Do not move it yourself.

## Git authorization

`docs/agent-rules.md` § Git carves this skill out. That authorization is narrow:

- Authorized, for the duration of this run, on the current branch: `git add` of files this run touched,
  `git commit` — one per completed task plus the final completion commit — and `git mv` within `prd/` at
  § Completion.
- Not authorized: everything else. Not `git push`, not `--amend`, not a new branch, not a PR. Each needs
  its own request from the user.

Everything else in `docs/agent-rules.md` § Git stands, including its absolutes: never `--no-verify`, never
force-push, never change git config.

## Preflight — once per run

1. `git diff --quiet && git diff --cached --quiet` — no tracked modifications and nothing staged.
   Untracked files are allowed and must not be added. One exception, on resume: uncommitted changes
   confined to `prd/backlog/<name>/project.md` and `progress.md` are this skill's own step-9
   bookkeeping — report them and continue; the next commit sweeps them in. Any other dirty tracked
   file: stop and ask. Do not stash, do not commit it.
2. `git branch --show-current` and `git rev-parse --short HEAD` — report both. All work stays on that
   branch; that sha is the run's **baseline**. Reviewers need it.
3. `bin/rails test` — green **before** the first edit. Red: stop (§ Stop conditions). A pre-existing
   failure must never be blamed on this PRD.
4. Read `project.md`. No `## Implementation Tasks` list → stop and ask. Do not invent tasks.
5. Read `progress.md` for the resume point; the ticked boxes in `project.md` are the authority. Create
   `progress.md` from § progress.md if the directory has none.
6. Report branch, baseline sha, task count, and the first unchecked task. Then start.

## The loop

Exactly one unchecked task at a time. Never batch. Never open the next task before the current one is
committed.

Each task line is `- [ ] FR-<n> — <task> — done when: <assertion> — proof: test/...` (format:
`.claude/skills/prd/SKILL.md` § Implementation Tasks). `done when:` is the acceptance criterion handed
to reviewers; `proof:` is the test that must exist and pass. A task missing either field is a stop.

1. **Restate.** One or two lines: the task, its `done when:`, its `proof:`.
2. **Implement.** The smallest change that satisfies it. Nothing from a later task, nothing the PRD
   lists under § Out of Scope. Naming, style, and security come from `docs/agent-rules.md`.
   - Already satisfied by the codebase — from an earlier task or from code that predates the PRD? Do
     not fabricate a diff and do not make an empty commit. Run the task's `proof:`. If it passes, tick
     the box, record `already satisfied — <the code that satisfies it>` in `progress.md`, and let the
     next task's commit carry that bookkeeping. If the `proof:` does not exist yet, the task is **not**
     satisfied — write the test.
3. **Test.** Write or extend the Minitest coverage named by `proof:`. A new guard gets a test that
   fails when the guard is removed.
4. **Gate.** Run `docs/agent-rules.md` § Quality steps 2-5 against the files this task touched — RuboCop
   **before** the tests, per that section. All clean before review.
5. **Review fan-out.** § Review fan-out. Nothing proceeds until the reviews are back.
6. **Triage.** § Triage.
7. **Re-gate.** Always, even when triage produced no fixes: the same `docs/agent-rules.md` § Quality steps
   as step 4, over the files as they now stand.
8. **Commit.** Only now, and only on a clean re-gate. One task = one commit. Stage the files this task
   touched plus the pending bookkeeping from step 9 of the previous task — never `git add -A`. A task
   that ran a migration stages the regenerated `db/schema.rb` alongside it; a migration committed
   without its schema dump breaks a fresh checkout. Confirm with `git status --porcelain` that the
   staged set is exactly the intended paths. Subject line: imperative, describing the behavior change,
   not the task number or the PRD name. Match `git log --oneline -10`; this repo uses no `feat:` /
   `fix:` prefixes.
9. **Record.** Tick the checkbox in `project.md`. Append the `progress.md` entry: task, sha from
   `git rev-parse --short HEAD`, what each reviewer found, what was deferred or rebutted. Both files
   stay uncommitted until the next task's commit sweeps them in — the sha does not exist before the
   commit, and amending to add it would change it.
10. **Next.** The next unchecked task, in order. Do not skip ahead. Reorder only when a later task
    blocks the current one, and write the one-line reason in `progress.md` first.

## Review fan-out

Spawn three subagents with the Task tool, **all in a single message**, so they run in parallel. One lens
each. They report; you fix. Reviewers do not edit files.

Before spawning, run `git add -N <every path this task created>`. `git diff` does not show untracked
files and nothing is staged yet, so without this a new test, service, view, controller, or migration is
invisible to all three reviewers.

Give every reviewer the same packet:

- the task line verbatim from `project.md`, including its `done when:` and `proof:`;
- § Security of `project.md`, verbatim — lens (b) works from it;
- § Out of Scope and § Affected Areas of `project.md`, verbatim — lens (a) works from them;
- the run's baseline sha, and the instruction to run `git diff <baseline-sha>` and
  `git status --porcelain` themselves. Never hand over a bare file list in place of a diff;
- an instruction to read `docs/agent-rules.md` first — in particular § Review tests, § Security, and
  § Attempt lifecycle;
- the return contract below.

**a. Rails-way, KISS & clean code.** Is this idiomatic Rails 8 *for this codebase*? Is there a simpler
construction with the same behavior? Does it add a layer `docs/agent-rules.md` § Style forbids? Does it duplicate
an existing service — read `app/services/` before answering. Does it copy a nearby precedent, or invent
a pattern that has none here? Then:

- Apply `docs/agent-rules.md` § Review tests — KISS, The Rails way, Clean code — as probes; report each
  miss as a finding. A bare user-visible literal in an ERB, a controller, or a flash is a `major` — name
  the file, the line, and the `uk.yml` key it should use.
- Does anything in the diff appear in the PRD's § Out of Scope?

**b. Security.** Read `docs/agent-rules.md` § Security and audit the diff against **every** rule in it — apply
them, do not re-derive them and do not work from a summary. Every line the PRD's § Security answered "yes"
needs a test in this diff or in an already-committed task. A "yes" with no test is a `critical` finding.

**c. Tests & correctness.** Does the new test actually fail without the change — state how you checked.
Does it assert the task's `done when:`, or something weaker? Edge cases and failure paths, not only the
happy path. N+1s: `test/integration/n_plus_one_test.rb` is the precedent. Anything touching
`AttemptLifecycle`: transaction boundaries, double submit, expiry races.

Return contract — hand it to each reviewer verbatim:

- One line per finding: `severity — file:line — problem — concrete fix`. Severity is `critical`,
  `major`, or `minor`.
- At most five findings, most severe first. Nothing to report: answer `No findings.` Say that instead
  of inventing something.
- You are reviewing a diff, not redesigning the feature. Out-of-scope redesign proposals are noise and
  will be discarded.

## Triage

- **critical / major** — fix before the commit. No exceptions, no deferral.
- **minor** — fix it if the fix lands inside files this task already touched and needs no new test;
  otherwise record it under `## Deferred` in `progress.md` with a one-line reason.
- **wrong, and `minor`** — write a rebuttal under `## Rebuttals` in `progress.md`: the lens, the
  finding, why it does not hold. Then proceed. Never drop one silently.
- **wrong, and `critical` or `major`** — you may not clear it yourself. Either fix it, or stop and ask
  the human (§ Stop conditions), quoting the finding and your rebuttal. A rebuttal of a `critical` or
  `major` must cite the `file:line` or the passing test that proves the finding false; without that
  citation the finding stands and you fix it.
- A security finding you cannot resolve without widening the task's scope is a stop condition, not a
  minor.

One review round per task. Triage fixes are not re-reviewed — except that if a fix for a `critical` or
`major` changes a student-facing path or an ownership scope, re-run lens (b) alone before the re-gate.
Never re-run the full fan-out on the same task. If that single re-review returns a further `critical` or
`major`, stop and ask.

## Gate escalation

Per task: § The loop steps 4 and 7. Nothing heavier.

`bin/ci` runs **once per PRD**: after the last task's commit and before the completion commit. Run it
earlier only when a task touches the `Gemfile`, an initializer, `db/seeds.rb`, or importmap pins.

What `bin/ci` covers, and how it differs from `.github/workflows/ci.yml`: `docs/agent-rules.md` § Quality.

## Completion

Every box ticked and `bin/ci` green:

1. `mkdir -p prd/complete && git mv prd/backlog/<name> prd/complete/<name>`.
2. Final `progress.md` entry: date, tasks completed, deferred items still open.
3. One commit for the move plus the outstanding bookkeeping.
4. Report: `git log --oneline <baseline-sha>..HEAD`, and what was deferred. Note that Brakeman runs
   stricter locally than on GitHub (`docs/agent-rules.md` § Quality), so a red local Brakeman is not
   proof the PR will be red.
5. Ask before pushing. This skill does not authorize it (§ Git authorization).

Stage moves are owned by `prd/README.md`. This skill performs exactly one of them, `backlog → complete`,
at step 1 above.

## Stop conditions

Halt and ask the human. Do not improvise around any of these:

- The suite was already red at preflight, or a tracked file was dirty at preflight.
- The PRD needs a schema change it does not describe, or its migration disagrees with `db/schema.rb`.
- A task turns on a decision `docs/agent-rules.md` § When to ask vs inspect flags as ask-first.
- A task line is missing its `done when:` or its `proof:`.
- A reviewer raises a security finding that cannot be resolved inside the task's scope.
- You believe a `critical` or `major` finding is wrong.
- A lens (b) re-review returns a further `critical` or `major` on the same task.
- The same gate fails twice in a row. Paste the failure; do not keep patching blind.
- The diff touches a path that is neither listed in § Affected Areas of `project.md` nor the task's
  `proof:` file. Name the stray path.
- The single `bin/ci` run is red. Report which step failed and what is already committed; do not open
  new work to chase it.

Say which condition fired, what is committed so far, and what you need to continue.

## progress.md

Append-only, newest entry last.

```markdown
## <task line, verbatim>
- commit: <short sha> <subject>
- reviews: rails/kiss <n> · security <n> · tests <n> — criticals/majors: <file:line>, ...
- fixed: <what the reviews changed>
- deferred: <item> → § Deferred   (or: none)
```

Two standing sections at the end of the file:

```markdown
## Deferred
- <finding> — <one-line reason> (task: <task text>)

## Rebuttals
- <finding> — <lens> — <why it does not hold> (task: <task text>)
```
