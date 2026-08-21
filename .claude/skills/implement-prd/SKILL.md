---
name: implement-prd
description: "Executes a local school-app PRD from prd/<name>/ on its own feature branch with targeted tests, risk-based review, and coherent implementation commits. Use only when the developer explicitly asks to execute, continue, or resume an existing PRD."
---

# Implement PRD

Execute `prd/<name>/project.md` with fast feedback during implementation and one broad verification pass
at the end. PRD files remain local and git-ignored.

`docs/agent-rules.md` is the canonical contract for domain naming, security, quality, and git. Read it
first; this skill only sequences the PRD work.

## Invocation

- `/implement-prd <name>` — execute `prd/<name>/project.md`.
- `/implement-prd` — list `prd/*/project.md` and ask which one. If none exists, stop.

Never infer this workflow from a normal implementation request. The developer must name the PRD flow.

## Git authorization

Invocation authorizes creating `feature/<name>` from clean `main`, then explicit staging and one or more
coherent implementation commits on that branch. A resume may continue only when already checked out on
that exact feature branch. Never stage or commit anything under `prd/`. It does not authorize push, amend,
switching to an existing branch, a PR, history rewriting, or any other exception to
`docs/agent-rules.md` § Git.

## Start

1. Read `project.md`. Require a goal, acceptance criteria, and at least one task; ask only if a missing or
   unresolved decision would change the implementation.
2. Inspect `git status`. A fresh run requires clean tracked and staged state on `main`; untracked files may
   remain and must not be added. Never stash or discard changes.
3. Derive `feature/<name>` from the PRD directory name and validate it with
   `git check-ref-format --branch`. For a fresh run, require that the branch does not exist, record HEAD as
   the baseline, and run `git switch -c feature/<name>`. For a resume, require the exact feature branch and
   use `git merge-base main HEAD` as the baseline. Any other branch state is a reason to stop and ask;
   never overwrite, delete, reset, or silently switch to an existing branch.
4. Read the ownership path and the tests named as proof. Run an existing proof test before editing only
   when distinguishing a pre-existing failure matters; do not run the whole suite as preflight.
5. Report the feature branch, baseline, task count, and first unchecked task, then begin.

## Implementation loop

Work in coherent vertical slices. Adjacent tasks may be combined when they implement one behavior and are
clearer to review together. Do not mix unrelated behavior into a slice.

1. **Implement and test.** Make the smallest complete change for the slice. Add or update the proof tests.
   If behavior already exists, run the proof and tick the task without fabricating a diff or commit.
2. **Targeted gate.** Run `bin/rubocop -A` on touched Ruby files first, then only the proof tests and other
   directly affected tests. Follow `docs/agent-rules.md` § Quality. Do not repeat a passing command unless
   later edits can affect it.
3. **Self-review.** Check KISS, Rails conventions, clean code, security, acceptance criteria, and the
   relevant edge cases against the finished slice.
4. **Review by risk.** Documentation, locale-only, and mechanical changes need no subagent. Use one
   correctness reviewer for a non-trivial diff when it adds useful independent scrutiny. Add a focused
   security reviewer only when the slice touches student-facing output, ownership/auth, `Take::`, tokens,
   params, broadcasts/jobs, scoring, schema, or `AttemptLifecycle`. Run both in parallel when both are
   needed. Reviewers inspect the diff and relevant rules; they report findings and do not edit.
5. **Resolve findings.** Fix findings that hold and reject incorrect ones with concrete code or test
   evidence. Ask the developer only when a high-impact product or security decision remains unresolved.
   Re-run only checks affected by fixes; re-review only a materially changed high-risk boundary.
6. **Commit.** Stage only implementation files from this slice by name, including `db/schema.rb` with any
   migration. Confirm the staged set, commit with an imperative behavior-focused subject, then tick the
   local PRD tasks covered by the commit. A small PRD may use one final implementation commit instead of a
   commit per task.

If implementation discovers a necessary related file or adjustment absent from the PRD, make the smallest
change and update the local PRD when that helps resume. Do not stop merely because the original plan did
not predict every file.

## Final verification

After all tasks are ticked:

1. Run `bin/rails test` once.
2. Run Brakeman when the finished implementation diff touches `app/`, Bundler Audit when it touches
   `Gemfile` or `Gemfile.lock`, and Importmap Audit when JS dependencies changed, using the commands in
   `docs/agent-rules.md` § Quality.
3. Fix failures, run the targeted check for each fix, then repeat only the final check that failed. Commit
   verified fixes as a coherent implementation commit.
4. Confirm `project.md` remains ignored and was never staged. Do not create `progress.md`.
5. Report implementation commits, decisive checks, and any unresolved follow-up. Do not push.

Stop and ask only for an overlapping user change, a hard-to-reverse decision covered by
`docs/agent-rules.md` § When to ask vs inspect, or a high-impact correctness/security ambiguity that direct
investigation cannot resolve. Diagnose ordinary test and tooling failures and continue.
