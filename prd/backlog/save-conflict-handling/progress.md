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

## Deferred
- Registering `config.action_dispatch.rescue_responses["AttemptLifecycle::Conflict"] = :conflict`.
  Rails maps `ActiveRecord::StaleObjectError` to `:conflict`, so between this commit and FR-2 a submit
  collision is a 500 where it used to be a 409. Not fixed here: the config path is outside this PRD's
  § Affected Areas, and FR-1/FR-2 close the gap entirely by stopping `Conflict` from reaching Rails'
  exception handling. Re-check after FR-2; if it is closed, no config entry is needed.
  (task: FR-3)

## Rebuttals
