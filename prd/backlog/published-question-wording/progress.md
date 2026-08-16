# Progress — published question wording

Run baseline: `bffdfa5` on `claude/published-exam-editing-6x7r6z`.
Suite green at preflight: 137 runs, 616 assertions, 0 failures.

Preflight note: the container had no gems installed (`bin/rails test` died in `Bundler::GemNotFound`
before loading the app). `bundle install` fixed it and left `Gemfile.lock` untouched — this is an
environment gap, not a red suite.

## FR-4 — Add the structure-freeze validation to `Question`, alongside the existing `config` validations, plus its `structure_frozen` error key
- commit: e719239 Refuse structural edits to a question once its test is published
- reviews: security 3 · tests 4 — criticals/majors: app/models/question.rb:163
- fixed: `config_skeleton` raised `NoMethodError` on a non-Hash entry in a text-bearing list, so a
  malformed `config` turned a rejection into a 500 from inside the validation — non-Hash entries now
  pass through whole, which also makes any change to one a structure change. The `source` exemption
  was unconditional, letting a published mcq/ordering/matching/short_text/open question gain or
  rewrite an arbitrary `config["source"]`; it is now scoped to `source?`. Both defects got a test and
  both were probed by reverting the fix: exactly the two new tests go red. Also had to switch the
  skeleton from `skeleton[key] =` to `merge`, because dropping the unconditional `except` meant
  `skeleton` could be the record's live `config` hash and in-place assignment would have mutated it.
  Tests: `valid?`-only assertions replaced by `update`/`save` plus reload checks, so the done-when's
  "saves" is actually proven; added a case that mutates `config` in place rather than reassigning,
  which is the shape the FR-1 wording form will use and the one the whole guard rests on; completed
  the draft case with `question_type`, `pairs` and `model_answer`, which were 3 of the 10 items the
  done-when enumerates.
- rebutted: none
- deferred: model freeze does not cover create/destroy on a published exam → § Deferred

## Deferred
- The `new_record?` early return means the model freeze does not cover adding or removing a question
  on a published exam — both still move `Exam#max_score` under finalized grades, and both are held
  only by `QuestionsController#ensure_editable`. Not fixed here: rejecting `new_record?` would break
  `create` and reaches past this task's done-when, and § Out of Scope keeps add/remove draft-only
  rather than enabling them. **Constraint on the FR-2/FR-3 task: the guard split must keep `create`
  and `destroy` on the structure guard, because this validation will not catch them.**
  (task: FR-4 — structure-freeze validation)
