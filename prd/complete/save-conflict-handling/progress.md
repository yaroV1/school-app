# Progress — save conflict handling

Run baseline: `1c3e5e4` on `claude/laravel-vs-rails-6yqlrh`.
Suite green at preflight: 122 runs, 534 assertions, 0 failures.

## FR-3 — Translate `ActiveRecord::StaleObjectError` raised inside `submit!`'s transaction into `AttemptLifecycle::Conflict`, adding no retry
- commit: fef00ae Raise Conflict instead of StaleObjectError when a submit collides
- reviews: rails/kiss 4 · security 1 · tests 3 — criticals/majors: test/services/attempt_lifecycle_test.rb:308, app/services/attempt_lifecycle.rb:126
- fixed: restubbed the submit test onto `Scoring.partial_total`, which `refresh_grade!` reaches after
  the status write — the previous stub raised before any write, making `assert in_progress?` vacuous
  (probe confirms: `submitted` inside the transaction, `in_progress` after rollback). Rewrote the
  service comment, which claimed the collision "reached the student as a 500" and that the controller
  rescue existed; neither was true. Trimmed the seven-line test-helper comment to two, inlined the
  `stale_object_error` helper, and added `assert_equal 0, attempt.answers.reload.count` so a
  rolled-back retry cannot silently duplicate answers.
- deferred: interim 409 → 500 status regression → § Deferred

## FR-1 — Rescue `AttemptLifecycle::Conflict` in `Take::AnswersController#upsert`
- commit: b1e7a5c Answer a conflicted autosave with the save_conflict message
- reviews: rails/kiss 3 · security 0 · tests 4 — criticals/majors: test/integration/save_conflict_test.rb:45, test/integration/save_conflict_test.rb:23-31
- fixed: replaced the vacuous `assert in_progress?` — `save_answers!` writes no status field, so it
  held with or without the rescue — with the property actually at stake: the next autosave succeeds
  and the answer persists. Both tests now go red when the rescue is removed. De-duplicated the
  swap-and-restore helper: `replacing` moved to `test_helper.rb`, the local copy in
  `attempt_lifecycle_test.rb` and the new `colliding` in the integration test both deleted. Dropped
  the redundant `refute_equal 500` and moved the real red/green mechanism into the file comment.
  Switched the fixture to `mcq` and named the production origin of the collision
  (`locked.update!(last_activity_at:)`), since `answers` carries no `lock_version`.
- deferred: none
- scope: touched `test/test_helper.rb`, which is outside § Affected Areas — see § Deferred note below.

## FR-2 — Rescue `AttemptLifecycle::Conflict` in `Take::SubmissionsController#create`
- commit: 17977a2 Return a conflicted submit to the run page instead of an error
- reviews: rails/kiss 1 · security 0 · tests 4 — criticals/majors: test/integration/save_conflict_test.rb:65-76, :78-88
- fixed: the rollback assertion was non-vacuous only by accident — it depends on `refresh_grade!`
  reaching `partial_total` after the status write, and `refresh_grade!` short-circuits on a
  teacher-finalized grade. Now the stub records the status at collision time and the test asserts
  `"submitted"`, so moving the stub earlier fails instead of passing quietly (verified). Added the
  grade assertions to the resubmit test, since `refresh_grade!` is the step that failed and the old
  test would have passed on a submit that skipped grading. Added `follow_redirect!` — a Location
  header does not prove the student sees a page. First test now submits with answers, covering the
  commoner path, and asserts they survive the rollback. Reworded the controller comment: `submit!`
  propagates `Conflict` from the answers write too, not only the status write.
- deferred: none — this task closed the FR-3 deferral (see § Deferred)

## FR-4 — Assert a conflicted submit broadcasts nothing
- commit: e8b80f2 Assert a conflicted submit stays silent to the teacher
- reviews: rails/kiss 4 · security 2 · tests 4 — criticals/majors: save_conflict_test.rb:132-135, :144, :141-144, :117-130
- fixed: the submit half of the token test was vacuous — `flash[:alert]` is nil on success, so the
  refute passed on a submit that never conflicted; it now asserts the redirect and the flash first
  (verified: without a conflict it fails on `/done` vs `/run`). Restored the submit-body token
  assertion after confirming actionpack 8.1 `redirect_to` sets an empty body, so the earlier
  narrowing was wider than it needed to be. Paired every `assert_empty` with a successful submit
  through the same keys, so stale capture keys fail loudly (verified). Split the token test in two
  so a payload regression cannot mask a flash leak. Extracted `conflicted_submit!`. Added the
  conflicted-autosave silence assertion.
- deferred: committed answers are never broadcast on a conflicted submit → § Deferred

## Deferred
- Registering `config.action_dispatch.rescue_responses["AttemptLifecycle::Conflict"] = :conflict`.
  Rails maps `ActiveRecord::StaleObjectError` to `:conflict`, so between this commit and FR-2 a submit
  collision is a 500 where it used to be a 409. Not fixed here: the config path is outside this PRD's
  § Affected Areas, and FR-1/FR-2 close the gap entirely by stopping `Conflict` from reaching Rails'
  exception handling. Re-check after FR-2; if it is closed, no config entry is needed.
  (task: FR-3)
  **CLOSED at 17977a2.** `Conflict` is raised only at attempt_lifecycle.rb:100 and :128, inside
  `save_answers!` and `submit!`. Their only callers are the two `Take::` actions that now rescue it;
  every other call site uses `start!` / `expire_if_needed!` / `expire_overdue!`, which reach neither.
  No `rescue_responses` entry is needed.
- `test/test_helper.rb` is not in § Affected Areas but was edited in b1e7a5c to host `replacing`.
  Hosting it there was the only way to clear a `major` (two copies of one helper) without a third
  copy. Flagged rather than silently widened; fold the path into § Affected Areas at § Completion.
  (task: FR-1)

- **A real gap, found by review, not fixed here.** A conflicted submit that carries answers commits
  them in `save_answers!`'s own transaction, which deliberately skips broadcasting on the promise
  that `submit!` will push one update for the lot (`attempt_lifecycle.rb` § save_answers! comment).
  `Conflict` breaks that promise: measured 1 answer durably committed, 0 grade_live and 0 live_board
  broadcasts, so the teacher's grading page never learns of work the student did. Pre-existing and
  outside this PRD, which only stops the exception escaping. Pinned by
  `test "a conflicted submit leaves committed answers unbroadcast"` so a fix must change that test
  deliberately. Candidate follow-up: have the `Conflict` rescue in `submit!` push
  `GradeLive.replace_answers` for whatever `save_answers!` returned. (task: FR-4)

## Rebuttals
- "Collapse into `rescue AttemptLifecycle::NotAllowed, AttemptLifecycle::Conflict => e` — the bodies are
  byte-identical" — rails/kiss — does not hold. § Affected Areas specifies "one `rescue` clause each,
  alongside the existing `Expired` and `NotAllowed` clauses", and the two conditions are semantically
  distinct: `NotAllowed` is a permanent state precondition, `Conflict` is transient contention the
  client should retry. Identical bodies today are a coincidence, not a shared meaning; merging them
  would have to be un-merged the moment either response diverges. (task: FR-1)
- "FR-1 is left unticked, so the committed backlog shows the wrong task done" — tests — does not hold.
  `.claude/skills/implement-prd/SKILL.md` step 9 requires the tick to follow the commit, because the
  sha does not exist beforehand, and says both files "stay uncommitted until the next task's commit
  sweeps them in". A one-task lag in the committed ticks is the documented design, not a slip.
  (task: FR-1)
