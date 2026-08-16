# Save conflict handling

## Overview

When two writes to the same attempt collide, `AttemptLifecycle` gives up after one retry and raises
`AttemptLifecycle::Conflict`. No `Take::` controller rescues it, so the student's submit ends on a Rails
error page and their work is not handed in. This makes the conflict path end in the message that already
exists for it — `take.errors.save_conflict` — so the student is told to try again instead of hitting a 500.

## Requirements

### Functional

- FR-1 (student) — An autosave that ends in a save conflict returns a JSON error carrying
  `take.errors.save_conflict`, not a 500. The attempt stays `in_progress` and previously saved answers are
  untouched.
- FR-2 (student) — A submit that ends in a save conflict returns the student to the run page with the
  `take.errors.save_conflict` alert and the attempt still `in_progress`, so they can submit again. No
  error page, no partial submission.
- FR-3 (student) — An `ActiveRecord::StaleObjectError` raised by `submit!`'s own transaction — a second,
  currently unhandled path — surfaces as the same `Conflict`, not as a raw exception.
- FR-4 (student) — A failed submit publishes nothing: no Turbo broadcast reaches the teacher's live board
  or grading page for an attempt that did not actually submit.

## Technical Approach

Two `rescue` clauses and one exception translation. Nothing new: no model, no service, no controller,
no gem, no Stimulus controller, no locale key.

The retry-once-then-`Conflict` policy in `save_answers!` is deliberately left alone — this PRD changes
only what happens to the exception after it is raised. Translating a raw `StaleObjectError` at the
service boundary (FR-3) is not a policy change: it adds no retry, it gives the existing failure a
domain-typed name so the controllers can catch one thing.

**No JavaScript change is needed.** `autosave_controller.js:82-86` already renders `data.error` from a
non-ok response into the status area. Today a 500 yields no parseable body, so it falls back to the
generic `take.save_failed`; returning a JSON error is enough to replace it with the specific message.

### Affected Areas

- Services: `app/services/attempt_lifecycle.rb` — translate `StaleObjectError` to `Conflict` in `submit!`.
  Reuses the existing `Conflict` class (`:5`); no new service — see `docs/agent-rules.md` § Style.
- Controllers: `app/controllers/take/answers_controller.rb`,
  `app/controllers/take/submissions_controller.rb` — one `rescue` clause each, alongside the existing
  `Expired` and `NotAllowed` clauses.
- Views: none. The autosave status area and the flash region already render this.
- Models: none.
- Jobs: none.
- Tests: `test/services/attempt_lifecycle_test.rb`, `test/integration/save_conflict_test.rb` (new).

`app/controllers/take/runs_controller.rb` is deliberately **not** in scope: `start!` never calls
`save_answers!`, so it cannot raise `Conflict`.

### Database Changes

`N/A — no schema change.` `attempts.lock_version` (`db/schema.rb:75`) already drives the optimistic
locking this feature reacts to.

### Routes

`N/A — no new or changed routes.` Both affected actions already exist:

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|
| PUT | `/t/:token/answers` | `student_answers_path` | `take/answers#upsert` | unauthenticated `Take::` |
| POST | `/t/:token/submit` | `student_submit_path` | `take/submissions#create` | unauthenticated `Take::` |

### Views & Hotwire

- **Views/partials**: none changed.
- **Stimulus**: none added or changed. `autosave` already handles the non-ok branch.
- **Turbo targets**: none.
- **Broadcasts**: none added. The point of FR-4 is the opposite — asserting that the existing
  `GradeLive.replace_header_and_answers` and `LiveBoard.replace` calls in `submit!` do **not** fire when
  the transaction rolls back, because they sit after the `Attempt.transaction` block.
- **New gem**: none.

## Security

- **Student-facing output** — no. No question data is rendered or serialized; the only new output is a
  translated error string. No new case is needed in `test/integration/answer_key_leak_test.rb`.
- **Teacher data** — no. Both actions are `Take::` and read nothing teacher-owned beyond the exam already
  loaded by `Take::BaseController#set_assignment`.
- **Unauthenticated `Take::`** — yes, two existing `Take::` actions change. Both continue to resolve
  through `Assignment.find_by!(access_token: params[:token])` in `Take::BaseController:11`, and reach the
  attempt only via `@assignment.attempts.find(...)`. No `Current.user` is introduced.
- **Assignment tokens** — yes, by omission. The FR-2 redirect passes `@assignment.access_token` to
  `student_run_path`, exactly as the existing `NotAllowed` rescue does (`submissions_controller.rb:10`).
  The error text is `I18n.t("take.errors.save_conflict")` and carries no token; the token must not appear
  in the flash, the JSON body, or any new log line. A test asserts the token is absent from the response
  body.
- **Params** — no new params. No `permit` list changes. The two documented `to_unsafe_h` exceptions in
  `docs/agent-rules.md` § Params are untouched.
- **Broadcasts and jobs** — yes, and the requirement is negative: nothing may be broadcast for an attempt
  that failed to submit. Covered by FR-4.

## Localization

`N/A — no new keys.` `take.errors.save_conflict` already exists at `config/locales/uk.yml:401`
("Не вдалося зберегти відповіді. Спробуйте ще раз.") and is currently raised but never displayed. This
PRD is what makes it reachable.

## UI/UX — User Flow

**Autosave conflict (FR-1)**

1. Student is on `/t/:token/run`. The `autosave` controller PUTs every 5s.
2. A write collides; `save_answers!` retries once, then raises `Conflict`.
3. The action returns a JSON error. The **autosave status region** (not a Turbo Frame) shows
   "Не вдалося зберегти відповіді. Спробуйте ще раз." in the failed state.
4. The next tick 5s later succeeds and the region returns to "Збережено". Nothing is lost.

**Submit conflict (FR-2)**

1. Student presses submit on `/t/:token/run`.
2. `submit!` raises `Conflict`; its transaction has rolled back, so the attempt is still `in_progress`.
3. Student is redirected back to `/t/:token/run` with the alert in the **flash region** of the
   `student` layout. The run page re-renders with their answers intact.
4. Pressing submit again succeeds.

## Edge Cases

- Conflict on the *last* autosave before the deadline: `Expired` is raised before `Conflict` is reachable,
  so the existing expiry path still wins. Assert the ordering does not change.
- Conflict on a submit that carries answers: `submit!` calls `save_answers!` first, so `Conflict` can
  arrive from either the answer write or the status write. Both must reach the same message.
- Attempt already `submitted` or `expired` by `ExpireAttemptJob` / `ExpireOverdueAttemptsJob` when the
  conflict resolves: `NotAllowed` / `Expired` take precedence and their current behavior is unchanged.
- Revoked token mid-flow: `set_assignment` still resolves (revocation is a column, not a delete) and
  `start!` guards it; no new path.
- Exam closed mid-attempt: unchanged — an in-progress attempt may still finish.

## Out of Scope

- Changing the retry count, the retry strategy, or the pessimistic/optimistic locking policy in
  `save_answers!`. Explicitly excluded by the request.
- Whether `Attempt.lock.find` takes a real row lock on SQLite. Flagged as unresolved in the doc audit and
  left open — this PRD is correct either way, because it only handles the exception.
- Retrying the submit automatically on the student's behalf. The student presses the button again.
- Any teacher-facing surface: grading, the live board, results.
- Client-side conflict UX beyond the message the existing status region already renders.
- Backfilling conflict coverage for `Take::RunsController` — it cannot raise `Conflict`.

## Open Questions

- Should the autosave conflict return `409 Conflict` rather than the `422 Unprocessable Entity` its two
  sibling rescues use? — non-blocking. Proposed: **422**, matching `Expired` and `NotAllowed` in the same
  method per `docs/agent-rules.md` § Style ("copy nearby code"). The client branches on `response.ok`, so
  it cannot tell the difference. Revisit only if an external client ever consumes this endpoint.
- `expire!` (`attempt_lifecycle.rb:146-152`) performs `locked.update!` with no transaction and no
  `StaleObjectError` handling, so it has the same latent hole as `submit!` did. — non-blocking, and
  deliberately excluded here: it is reached from a background sweep as well as a request, so the right
  response differs. Worth its own PRD.

## Testing Strategy

Conflicts are provoked deterministically by stubbing, not by real concurrency — a threaded test against
SQLite would be flaky and would prove less.

- `test/services/attempt_lifecycle_test.rb` — extend: `save_answers!` raises `Conflict` after exactly one
  retry when `StaleObjectError` persists (pins the policy this PRD must not change); `submit!` raises
  `Conflict`, not `StaleObjectError`, when its own transaction collides.
- `test/integration/save_conflict_test.rb` — new, the pattern to copy is
  `test/integration/grade_integrity_test.rb`. Proves the request-level contract: autosave returns the
  translated error and no 500; submit redirects to the run page with the alert and leaves the attempt
  `in_progress`; the access token appears nowhere in either response body.
- `test/integration/mvp_flow_test.rb` — **not** extended. The happy-path spine does not change.
- Every "yes" in § Security has a test: the `Take::` scoping is exercised by both new request tests, the
  token-absence assertion is explicit, and FR-4 asserts the negative broadcast case.

Quality loop and commands: `docs/agent-rules.md` § Quality.

## Implementation Tasks

One commit per task.

- [x] FR-3 — Translate `ActiveRecord::StaleObjectError` raised inside `submit!`'s transaction into
      `AttemptLifecycle::Conflict`, adding no retry — done when: `submit!` raises `Conflict` and never
      `StaleObjectError` when its transaction collides, and `save_answers!` still retries exactly once
      before raising — proof: `test/services/attempt_lifecycle_test.rb`
- [x] FR-1 — Rescue `AttemptLifecycle::Conflict` in `Take::AnswersController#upsert`, returning the
      translated message as JSON alongside the existing `Expired` and `NotAllowed` clauses — done when: a
      conflicting autosave responds non-2xx with a body containing `take.errors.save_conflict`, the
      response is not a 500, and the attempt is still `in_progress` — proof:
      `test/integration/save_conflict_test.rb`
- [x] FR-2 — Rescue `AttemptLifecycle::Conflict` in `Take::SubmissionsController#create`, redirecting to
      `student_run_path` with the alert — done when: a conflicting submit redirects to the run page with
      `take.errors.save_conflict` in the flash, the attempt is still `in_progress`, and no error page is
      rendered — proof: `test/integration/save_conflict_test.rb`
- [x] FR-4 — Assert a conflicted submit broadcasts nothing — done when: no `GradeLive` or `LiveBoard`
      broadcast is emitted for an attempt whose submit raised `Conflict`, and the access token appears in
      neither conflict response body — proof: `test/integration/save_conflict_test.rb`
