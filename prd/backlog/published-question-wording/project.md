# Published question wording

## Overview

`Exam#questions_editable?` is `draft?`, and `QuestionsController` gates every write on it, so once a test
is published a teacher cannot fix a typo in a question while students are sitting it. This lets a teacher
correct the **wording** of a published question — the prompt, the source text, and the display text of
existing options, ordering items and matching entries — while the structure that grading depends on stays
frozen. Students see the corrected text; nothing already answered or graded moves.

## Requirements

### Functional

- FR-1 (teacher) — A teacher can correct a question's `prompt` while the exam is `draft` or `published`.
  A `closed` exam rejects the edit and says so.
- FR-2 (teacher) — In the same states a teacher can correct the display text of entries that already
  exist: MCQ option text, ordering item text, matching left and right text, and the `source` text of a
  `source` question. A blank input leaves that entry's existing text unchanged, matching how the add-question
  form ignores blank rows.
- FR-3 (teacher) — Adding and removing questions still requires `draft`. That guard is unchanged, and its
  flash message stops claiming that *all* question edits are draft-only.
- FR-4 (teacher) — Once an exam leaves `draft`, structure is frozen at the model, so any writer — controller,
  console, a future action — is refused, not just the wording form. Frozen: `points`, `question_type`,
  `position`, every option/item/left/right `id`, the count and order of those arrays, `is_correct`, the
  `pairs` map, `rubric`, and `model_answer`.
- FR-5 (both) — A wording edit moves no recorded work: no `answers.auto_score`, no `answers.teacher_score`,
  no `grades` row, and `Exam#max_score` is unchanged. This holds for attempts that are in progress,
  submitted, expired, and teacher-finalized.
- FR-6 (student) — A student who reloads the run page sees the corrected text. The edit adds no
  student-facing field and exposes no answer key, and it does not reshuffle an ordering question under a
  student mid-attempt.

## Technical Approach

Nothing new in the § KISS gate sense: no table, no column, no model, no controller, no service, no gem,
no Stimulus controller. Two predicates, one validation, a narrowed `update` path, and one view partial.

**Why the freeze lives in `Question`, not a service.** The rule is a record-level invariant with one
writer, and `Question` already owns four sibling `config` validations (`mcq_has_correct_option`,
`ordering_has_items`, `matching_has_pairs`, `source_has_text`) — a validation sits next to them. A service
under `app/services/` was considered and rejected: it would have one caller and would move the invariant
away from the record it constrains, where a console write would bypass it.

**Why wording cannot reuse `apply_config!`.** `QuestionsController#apply_config!` rebuilds `config` from
scratch. For MCQ it recomputes `is_correct` from `correct_index`, and with no radio in a wording form that
parameter is absent, so its fallback would move the correct answer to the first option. `apply_matching_config!`
likewise mints fresh `pairs`. The wording path therefore overwrites `text` values keyed by their existing
`id` and touches nothing else; the FR-4 validation is the backstop that proves it.

**Why texts are safe and `points` is not.** `Scoring` keys on ids alone — `score_mcq!` compares
`answer.option_id` to `correct_option_id`, `score_ordering!` compares arrays of ids, `score_matching!`
compares an id→id map. Changing an entry's display text moves no score. `points` is the opposite: it is
multiplied into `auto_score` (`scoring.rb:21,30,45`), snapshotted into `grade.max_score`
(`attempt_lifecycle.rb:187`) which `refresh_grade!` deliberately will not move once a teacher has
finalized, and divided into the subject percentage (`subject.rb:41`). It is out of scope — see
§ Out of Scope.

### Affected Areas

- Models: `app/models/exam.rb` — add `wording_editable?`. `app/models/question.rb` — add the structure-freeze
  validation and a private skeleton helper.
- Controllers: `app/controllers/questions_controller.rb` — split `ensure_editable` into a structure guard
  (`create`, `destroy`) and a wording guard (`update`); rewrite `update` to apply wording only; add a
  narrow permit list beside the existing `question_params`.
- Views: `app/views/exams/show.html.erb` — render the wording form per question.
  `app/views/questions/_wording_form.html.erb` — new partial, alongside the existing `_photo` partial.
- Services: none. `Scoring` and `AttemptLifecycle` are read for FR-5 assertions and not modified.
- Jobs: none.
- Tests: `test/models/question_test.rb`, `test/models/exam_test.rb`,
  `test/integration/question_wording_test.rb` (new), `test/integration/grade_integrity_test.rb`,
  `test/integration/answer_key_leak_test.rb`.

### Database Changes

`N/A — no schema change.` Wording lives in `questions.prompt` (`db/schema.rb:136`) and in the existing
`questions.config` JSON (`db/schema.rb:131`).

### Routes

`N/A — no new or changed routes.` The action already exists and is already reachable:

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|
| PATCH | `/tests/:test_id/questions/:id` | `test_question_path` | `questions#update` | teacher |

Today no view posts to it and no test covers it — it is a dead path. This PRD gives it its one job.

### Views & Hotwire

- **Views/partials**: `app/views/questions/_wording_form.html.erb`, new, rendered inside the existing
  question `<li>` in `app/views/exams/show.html.erb`. Shown when `@exam.wording_editable?`. Not a Turbo
  Frame — `update` redirects to `test_path`, exactly like every other form on that page.
- **Stimulus**: none added. The form is collapsed behind a native `<details>` disclosure so the question
  list stays readable; adding a controller to toggle visibility was rejected against the existing `dismiss`
  controller, which handles flash dismissal and does not fit.
- **Turbo targets**: none.
- **Broadcasts**: none. A wording change is not an attempt transition, so neither `LiveBoard` nor
  `GradeLive` fires — see § Out of Scope for the student-side push that is deliberately excluded.
- **New gem**: none.

## Security

- **Student-facing output** — no new field. `app/views/take/runs/show.html.erb` already renders
  `question.prompt`, `student_facing_options`, `display_items_for`, `student_facing_left`,
  `shuffled_right_items` and `source_text`; this changes what those return, not what is sent. No new
  question type, so no new case in `test/integration/answer_key_leak_test.rb` — but FR-6 extends it with an
  assertion that the page still leaks nothing *after* a wording edit, which is what would fail if the
  wording path ever wrote a key into a student-visible slot.
- **Teacher data** — yes, read and write. `set_exam` keeps `Current.user.exams.find(params[:test_id] || params[:exam_id])`
  and the question is reached only through `@exam.questions.find(params[:id])`. No bare-id load is
  introduced; a PATCH from another teacher 404s.
- **Unauthenticated `Take::`** — no `Take::` action is added or changed, and no `Current.user` reaches
  `app/controllers/take/`.
- **Assignment tokens** — not touched. No token reaches the wording form, the flash, the validation
  message, or any new log line; the feature adds no export, fixture, or broadcast that could carry one.
- **Params** — yes, three: `question[prompt]`, `question[source]`, and `question[texts][<entry id>]`.
  They land in a new narrow permit list `permit(:prompt, :source, texts: {})`, separate from the existing
  `question_params` that `create` uses. `texts: {}` permits an id→string map whose keys are not known in
  advance; it is a `permit` list, not `to_unsafe_h`, so it adds no third exception to
  `docs/agent-rules.md` § Params. Unknown ids are ignored rather than creating entries, and FR-4 rejects the
  record if they were not.
- **Broadcasts and jobs** — none added, nothing enqueued. No teacher stream reaches a student.

## Localization

| Key | Ukrainian text |
|---|---|
| `exams.show.edit_wording` | Виправити текст |
| `exams.show.save_wording` | Зберегти виправлення |
| `exams.show.wording_hint` | Змінюється лише текст. Бали, тип, набір варіантів, правильна відповідь і пари лишаються незмінними. |
| `exams.show.wording_options` | Тексти варіантів |
| `exams.show.wording_items` | Тексти подій |
| `exams.show.wording_pairs` | Тексти пар |
| `exams.flash.wording_locked` | Текст питання можна виправляти, доки тест не закрито. |
| `activerecord.errors.models.question.attributes.base.structure_frozen` | Опубліковане питання можна виправляти лише текстово: бали, тип і структура незмінні. |

One existing key changes, because it is now inaccurate — it currently claims every question edit is
draft-only, and after FR-1 only adding and removing are:

| Key | Was | Becomes |
|---|---|---|
| `exams.flash.questions_locked` | Питання можна змінювати лише в чернетці. | Додавати й видаляти питання можна лише в чернетці. |

Reused, not re-added: `exams.show.prompt`, `exams.show.source`, `exams.show.matching_left`,
`exams.show.matching_right`, `exams.flash.question_updated`.

## UI/UX — User Flow

1. Teacher opens `test_path(@exam)` for a published test. Each question in the **question list** region
   renders as today, with a collapsed "Виправити текст" disclosure beneath the prompt. The "Видалити"
   button and the whole "Додати питання" section stay hidden — those are still draft-only.
2. Teacher expands it. The **disclosure body** shows a prompt textarea, a source textarea for a `source`
   question, and one text input per existing option / item / left+right entry, each prefilled. There is no
   radio, no add-row, no delete-row, and no points field. The hint states what is frozen.
3. Teacher submits. `questions#update` writes prompt and texts, redirects to `test_path(@exam)` with the
   existing `exams.flash.question_updated` notice in the **flash region**.
4. A student who loads or reloads `/t/:token/run` sees the corrected text. Their in-flight answers are keyed
   by id and are untouched; an ordering question does not reshuffle.
5. On a `closed` test the disclosure is absent, and a direct PATCH redirects to `test_path(@exam)` with
   `exams.flash.wording_locked`.

## Edge Cases

- **Ordering shuffle stability.** `Question#stable_seed` hashes `id`, the attempt seed and a suffix — never
  the item text — so a wording edit does not reshuffle a list under a student mid-attempt.
- **Student holding the page open.** Their DOM carries the old text, and their payload carries ids, so a
  submit after the edit scores identically. They see the correction only on reload; excluded by choice.
- **Attempt already submitted, expired, swept by `ExpireOverdueAttemptsJob`, or teacher-finalized.** No
  `answers` or `grades` row is written, so every one of these is inert. A finalized grade in particular must
  not move — `refresh_grade!` guards it and this path never reaches it.
- **Draft exam.** The wording form is available there too, and the FR-4 validation does not apply, so a
  draft question can still be restructured — by removing and re-adding it, exactly as today.
- **Question with no config** (`short_text`, `open`). The form is prompt only; no text inputs render.
- **Blank prompt** — rejected by the existing `validates :prompt, presence: true`. **Blank source** —
  rejected by the existing `source_has_text`. **Blank entry text** — ignored, existing text kept (FR-2).
- **Unknown or stale id in `texts`** — ignored; it must not create an entry, and FR-4 refuses the record if
  it did.
- **Another teacher's question.** `Current.user.exams.find` raises `ActiveRecord::RecordNotFound` → 404.
- **Single question, and a large class.** The form renders inside the existing `@questions` loop, which
  `ExamsController#show` already loads as `@exam.questions.with_attached_photo`. No new query per question
  and no new collection, so `test/integration/n_plus_one_test.rb` needs no extension.

## Out of Scope

- Editing `points` after publication, and any rescoring policy it would need: recomputing `auto_score` on
  recorded answers, moving `grade.max_score` on finalized grades, or restating `Subject` percentages. Its
  own PRD.
- Changing `question_type` or `position` after publication.
- Adding or removing questions, options, items, or pairs after publication.
- Changing which MCQ option is correct, the ordering item order, or the `pairs` map.
- Editing `rubric` or `model_answer` after publication — see § Open Questions.
- Pushing the corrected text to a student who already has the run page open. Reload is enough; a
  student-facing broadcast would be the first in the app and is not worth it for a typo fix.
- A full structural question editor for draft exams. Remove-and-re-add stays the way to restructure a draft.
- Any audit trail of who changed a question's wording and when.

## Open Questions

- Should `rubric` and `model_answer` be editable after publication too? — non-blocking. They are
  teacher-only, never student-visible, and scoring-neutral for the three teacher-scored types, so the
  argument for allowing them is as strong as for the prompt. Excluded here only because the developer scoped
  this PRD to text students can see. FR-4 freezes them, so allowing them later is a one-line change to the
  skeleton helper plus two form fields.
- Should a teacher see that a question was corrected mid-exam, and when? — non-blocking. There is no
  audit column on `questions` and adding one is a schema change; `updated_at` already moves and could carry
  a "виправлено" hint on the question list if that turns out to be enough.

## Testing Strategy

- `test/models/question_test.rb` — extend: the structure-freeze validation. A wording-only change to a
  published question is valid; a change to `points`, `question_type`, `position`, an option `id`,
  `is_correct`, an array's length or order, the `pairs` map, `rubric`, or `model_answer` is not. The same
  changes on a draft question stay valid. This is the test that fails if the guard is removed.
- `test/models/exam_test.rb` — extend: `wording_editable?` is true for `draft` and `published`, false for
  `closed`, while `questions_editable?` stays `draft`-only.
- `test/integration/question_wording_test.rb` — new; the pattern to copy is
  `test/integration/assignments_manage_test.rb`. Request level: a PATCH on a published exam updates prompt
  and entry texts and redirects with the notice; a PATCH carrying `points`, `question_type` or new option
  rows changes nothing; a PATCH on a closed exam redirects with `wording_locked`; POST and DELETE on a
  published exam still redirect with `questions_locked`; a PATCH by another teacher 404s; the published
  page renders the wording form and renders neither the remove button nor the add-question section.
- `test/integration/grade_integrity_test.rb` — extend for FR-5: after a wording edit on an exam that has an
  in-progress attempt, a submitted attempt and a teacher-finalized one, every `auto_score`, `teacher_score`,
  `grade.total_score`, `grade.max_score` and `Exam#max_score` is byte-for-byte what it was before.
- `test/integration/answer_key_leak_test.rb` — extend for FR-6: re-run the leak assertions on the student
  run page after a wording edit, and assert the ordering item order is identical across two loads for the
  same attempt.
- `test/integration/mvp_flow_test.rb` — **not** extended. The teacher → assign → take → grade spine does not
  change.
- `test/integration/n_plus_one_test.rb` — **not** extended; no new collection or per-question query.

Every "yes" in § Security has a test: the teacher scope by the cross-teacher 404 case, the params list by
the tampering cases, and the student-facing boundary by the extended leak test.

Quality loop and commands: `docs/agent-rules.md` § Quality.

## Implementation Tasks

One commit per task.

- [x] FR-4 — Add the structure-freeze validation to `Question`, alongside the existing `config`
      validations, plus its `structure_frozen` error key — done when: on a published exam a text-only
      `config` change saves, and a change to `points`, `question_type`, `position`, any entry `id`,
      `is_correct`, an array's length or order, `pairs`, `rubric`, or `model_answer` fails with the
      translated message, while all of them still save on a draft exam — proof: `test/models/question_test.rb`
- [ ] FR-1 — Add `Exam#wording_editable?` beside `questions_editable?` — done when: it is true for `draft`
      and `published` and false for `closed`, and `questions_editable?` still answers `draft` only —
      proof: `test/models/exam_test.rb`
- [ ] FR-2, FR-3 — In `QuestionsController`, split `ensure_editable` into a structure guard on
      `create`/`destroy` and a wording guard on `update`, rewrite `update` to write only `prompt`, `source`
      and `texts` keyed by existing id through a new narrow permit list, and add the `wording_locked` and
      reworded `questions_locked` keys — done when: a PATCH on a published exam updates prompt and entry
      texts, a PATCH additionally carrying `points`, `question_type` or new option rows leaves the record
      unchanged, a blank entry text keeps the existing text, an unknown id creates nothing, a PATCH on a
      closed exam redirects with `wording_locked`, POST and DELETE on a published exam still redirect with
      `questions_locked`, and a PATCH by another teacher 404s — proof:
      `test/integration/question_wording_test.rb`
- [ ] FR-1 — Add `app/views/questions/_wording_form.html.erb` and render it per question in
      `app/views/exams/show.html.erb` when `@exam.wording_editable?`, with the `exams.show.*` wording keys —
      done when: the published test page renders a prefilled prompt textarea and one text input per existing
      option, item and matching entry, renders no points field, no radio and no add- or remove-row control,
      and still renders neither the remove button nor the add-question section — proof:
      `test/integration/question_wording_test.rb`
- [ ] FR-5 — Assert a wording edit moves no recorded work — done when: for an exam with an in-progress, a
      submitted and a teacher-finalized attempt, every `auto_score`, `teacher_score`, `grade.total_score`,
      `grade.max_score` and `Exam#max_score` is unchanged after the edit — proof:
      `test/integration/grade_integrity_test.rb`
- [ ] FR-6 — Assert the student boundary survives a wording edit — done when: the run page rendered after an
      edit exposes the corrected text and no rubric, model answer, `is_correct`, or `pairs` value, and an
      ordering question returns the same item order across two loads for the same attempt — proof:
      `test/integration/answer_key_leak_test.rb`
