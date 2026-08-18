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

## FR-1 — Add `Exam#wording_editable?` beside `questions_editable?`
- commit: 0c78b21 Separate the wording gate from the structure gate on an exam
- reviews: security 1 · tests 2 — criticals/majors: none
- fixed: both lenses independently flagged the same thing — `!closed?` is a denylist that fails open,
  where the sibling `questions_editable?` is an allowlist. The tests lens probed it:
  `Exam.new(status: nil).wording_editable?` returned `true` while `questions_editable?` returned
  `false`. For a predicate whose job is to gate writes to a live exam the safe failure mode is
  deny-by-default, so it is now `draft? || published?` — which is also literally the done-when's
  wording — plus a test pinning that an untaught status denies. Probed the new test against the old
  form: it goes red. The state test also reached `published` through `update!` on an exam with no
  questions, a state the app cannot produce (`publish!` raises when `questions.none?`); it now adds a
  question and uses `publish!` / `close!`, the real transitions.
- rebutted: none
- deferred: none

Self-inflicted note: the first version of the untaught-status test asserted on `Exam.new`, which the
column default makes `draft` — so it failed correctly and the test was wrong, not the predicate.

## FR-2, FR-3 — In `QuestionsController`, split `ensure_editable` into a structure guard on `create`/`destroy` and a wording guard on `update`, rewrite `update` to write only `prompt`, `source` and `texts` keyed by existing id through a new narrow permit list, and add the `wording_locked` and reworded `questions_locked` keys
- commit: 0766676 Let a teacher correct question wording while a test is running
- reviews: security (round 1: the nested-`texts` hole; lens (a) re-review after the fix: no findings) ·
  tests 5 — criticals/majors: app/controllers/questions_controller.rb:64,
  test/integration/question_wording_test.rb:82, test/integration/question_wording_test.rb:8
- fixed: `texts: {}` was not narrow at the leaf — it permitted arbitrary nesting, so a request could
  store a Hash, an Array or a number as an entry's `text`, and the student run page renders whatever
  lands there. The model guard did not catch it either, because `config_skeleton` strips `text` before
  the structure comparison, so this was the one shape both guards were blind to. `reworded_entry` now
  accepts only a present String. The re-review re-ran both original exploits plus JSON bodies carrying
  a number, `true`, `null` and an array of objects: all refused, every stored `text` still a `String`,
  and the narrowing opened nothing new. Tests: three of the nine passed against the pre-change
  controller that redirects every PATCH with `questions_locked`, so they proved nothing — the
  unknown-id case re-sent the prompt the question already had and asserted only that the options were
  untouched, and the blank-prompt case asserted only `flash[:alert].present?`, which the lock redirect
  satisfies just as well. Both now assert what only a save that actually ran can produce. `ordering`
  and `matching` had no coverage at all, leaving three of the four `TEXT_BEARING_KEYS` unexercised and
  `matching` — the type where a mis-keyed rewrite would silently disturb `pairs` — untested; both are
  covered now, asserting `pairs` and `correct_order_ids` are byte-identical after a text rewrite.
- rebutted: the suggestion to skip a blank `source` the way a blank entry text is skipped. FR-2's
  "blank leaves it unchanged" is about entries in a list; `source` is a single required field like
  `prompt`, and § Edge Cases already chose rejection for it. Kept the rejection and added the test that
  was missing in both directions.
- deferred: none

## FR-1 — Add `app/views/questions/_wording_form.html.erb` and render it per question in `app/views/exams/show.html.erb` when `@exam.wording_editable?`, with the `exams.show.*` wording keys
- commit: 4e0a3f3 Give the teacher a form to fix a question's wording
- reviews: security 0 · tests 4 — criticals/majors: app/views/questions/_wording_form.html.erb:11,
  test/integration/question_wording_test.rb:222
- fixed: `f.text_area :prompt` emits `id="question_prompt"` for every form it renders, and the source
  textarea hardcoded `id="question_source"`, so a page with N questions carried N+1 copies of the same
  id. `for=` binds to the first match, which meant the add-question form's own label had started
  focusing question #1's wording textarea — a regression this task introduced on the draft page. Ids
  are now `dom_id(question, :prompt)` / `dom_id(question, :source)`, pinned by a test that counts the
  bare id and asserts uniqueness; probed by reverting the fix, and it goes red. Tests: nothing capped
  the number of fields, so a partial that also rendered a blank add-row input or a per-row remove
  button would have passed — the counts are now exact per type and `button` is asserted absent. Added
  a `short_text` question, the case where every entry list is empty and only the prompt renders, and a
  draft-page test covering the state where the wording form sits beside the delete button and the
  add-question section.
- rebutted: none
- deferred: none

Beyond the PRD's § Localization table: `exams.show.publish_confirm` told the teacher "Питання після
цього не можна змінювати", which the FR-2/FR-3 commit made false. Reworded here rather than left to
misinform at the moment of the decision; both reviewers were asked to judge it as possible scope creep
and both accepted it. No test pins the literal — `exam_tabs_test.rb:49` goes through `t()`.

Self-inflicted note: ran `bin/rubocop -A` over the `.erb` and `.yml` files, which it parses as Ruby —
693 phantom offenses and an autocorrect pass that thankfully could not rewrite what it could not
parse. Verified both files against `git diff` before committing. Lint Ruby only.

## FR-5 — Assert a wording edit moves no recorded work
- commit: f28547a Prove a wording fix leaves recorded work untouched
- reviews: security 2 · tests 2 — criticals/majors: test/integration/grade_integrity_test.rb:148
- fixed: the in-progress attempt was passing by construction — a wording PATCH writes only to
  `questions`, so nothing could move that attempt's stored `auto_score` inside the assertion window,
  and the state where a mid-exam student's work genuinely can move is `AttemptLifecycle.submit!`,
  which runs `Scoring.score_all_auto!` against the config as it then stands. The test now submits
  after the edit and asserts the rescore lands on the same option. The snapshot compared scores but
  not the answers themselves: a probe rewriting every student's `payload` passed green, so `payload`
  is now in the compared tuple. Added the missing anti-vacuity pins for `teacher_score`,
  `grade.max_score` and `Exam#max_score` — three of the five values the done-when names were
  unpinned, so the equality could have gone on passing on nothing. Added a broadcast check for the
  PRD's "none added" claim and § Out of Scope's "no push to a student mid-exam".
- rebutted: none
- deferred: none

Two mistakes of mine worth recording. `assert_no_turbo_stream_broadcasts` calls the block and then
counts **every** broadcast on the stream, not the delta — unlike `assert_turbo_stream_broadcasts`,
which with a block does take a delta. My first version therefore failed on the `autosave!` pushes this
test makes in its own setup, and I misread that as a stray push from the controller; the reviewer's
measurement was right and my assertion was wrong. The broadcast check is now an explicit before/after
count. Separately, my first probe run injected nothing at all — `if @question.save` appears in both
`create` and `update`, so the uniqueness guard in the injection script aborted and the suite ran green
against an unmodified controller. A green probe that proves nothing is worse than no probe; re-ran it
against a unique anchor, and both injected breaks turn the test red.

Reviewer note carried forward: the two review agents probe by editing the same working tree, and this
round they collided — a `points: 99` probe from one appeared mid-run in the other's suite and produced
transient `SQLite3::BusyException` failures. Future fan-outs should tell reviewers to copy the repo
before mutating it.

## FR-6 — Assert the student boundary survives a wording edit
- commit: 7cd8af6 Hold the answer-key boundary across a wording fix
- reviews: security 4 · tests 4 — criticals/majors: test/integration/answer_key_leak_test.rb:94-118
  (both lenses, independently)
- fixed: the `MODEL_ANSWER` refutation was vacuous — `@open` is the only question whose config holds a
  model answer and the test never PATCHed it, so that assertion was inherited from an unedited question
  and added nothing over the test that already existed. Both reviewers demonstrated the same probe:
  append `config["model_answer"]` to an open question's prompt inside `apply_wording!` and everything
  stays green. The fourth PATCH is in, and the probe now turns it red. The ordering comparison passed on
  `[] == []`, so a renamed field would have slipped through — `refute_empty` guards it, mirroring the
  neighbouring test at :74. `assert_no_answer_key` read `@matching.pairs` from the setup-time in-memory
  record rather than what is stored after the edit; it reloads now. `assert_redirected_to test_path`
  could not distinguish a successful edit from a refused one — both `ensure_wording_editable` and the
  save-failure branch redirect to the same path — so the edits are pinned by their flash instead. Added
  an assertion that no option renders pre-checked, which is the answer key wearing a different shape.
- rebutted: none
- deferred: a value-shaped leak through the right-column order → § Deferred

## Deferred
- The `new_record?` early return means the model freeze does not cover adding or removing a question
  on a published exam — both still move `Exam#max_score` under finalized grades, and both are held
  only by `QuestionsController#ensure_editable`. Not fixed there: rejecting `new_record?` would break
  `create` and reaches past that task's done-when, and § Out of Scope keeps add/remove draft-only
  rather than enabling them. **Constraint honoured by the FR-2/FR-3 task: `create` and `destroy` stayed
  on the structure guard.** (task: FR-4 — structure-freeze validation)
- `assert_no_answer_key` matches key *names* and pair *ids*, so a leak that emits the key as a *value* —
  the right column ordered to mirror `pairs` — is not covered. The suggested `refute_equal` cannot be
  taken as-is: the matching fixture has two pairs, so the shuffle coincides with the key half the time
  by construction and the assertion would be a coin flip that already fails today. Making it meaningful
  needs a wider matching fixture, which is its own change. The pre-checked-radio half of the same
  finding was fixed. (task: FR-6 — student boundary)

## Run complete — 2026-08-18

6 of 6 tasks committed, baseline `bffdfa5` on `claude/published-exam-editing-6x7r6z`.
`bin/ci` green in one run after the last task: 169 runs, 853 assertions, 0 failures.

Still open, both recorded above under § Deferred: the model-level freeze does not cover adding or
removing a question on a published exam (held by the controller guard instead), and the answer-key
helper does not cover a key that leaks as a value through the right column's order.
