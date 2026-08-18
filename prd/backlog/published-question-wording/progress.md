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

## Deferred
- The `new_record?` early return means the model freeze does not cover adding or removing a question
  on a published exam — both still move `Exam#max_score` under finalized grades, and both are held
  only by `QuestionsController#ensure_editable`. Not fixed here: rejecting `new_record?` would break
  `create` and reaches past this task's done-when, and § Out of Scope keeps add/remove draft-only
  rather than enabling them. **Constraint on the FR-2/FR-3 task: the guard split must keep `create`
  and `destroy` on the structure guard, because this validation will not catch them.**
  (task: FR-4 — structure-freeze validation)
