# Printed test and parent report

## Overview

Nothing in this app can be put on paper. A teacher whose room loses power, or whose class has one
tablet between four, has no fallback; and a parent who asks how their child did gets a screenshot of
a grading form built for the teacher. This adds three print-ready pages — a blank paper copy of a
test for students, a matching answer-key copy for the teacher, and a one-attempt report a parent can
be handed — each laid out so the browser's own **Print → Save as PDF** produces the document.

The blank student copy and the parent report are the two surfaces that leave the teacher's screen.
Neither may carry an answer key.

## Requirements

### Functional

- FR-1 (teacher) — From a test in any status (`draft`, `published`, `closed`) a teacher can open a
  printable paper copy. It carries the class, subject and test title, blank name/class/date lines,
  the total points, and every question in `position` order with its number, type label, points,
  prompt and photo.
- FR-2 (student) — The paper copy carries **no answer key**. Every question renders through the
  `Question` student-facing readers only, and each type gets blank space to answer by hand: unticked
  boxes for `mcq`, ruled lines for `short_text` / `open` / `source`, numbered boxes for `ordering`,
  a lettered option bank plus a blank per left item for `matching`.
- FR-3 (teacher) — A separate answer-key copy carries the same questions with the answers: the
  correct `mcq` option marked, `ordering` items in `correct_order_ids` order, every `pairs` entry as
  left → right, and the `rubric` and `model_answer` for the teacher-scored types. It is reachable
  only from the paper copy's own page and never from a student surface.
- FR-4 (teacher) — Printing any of the three pages produces a clean sheet: no app header, no tabs,
  no breadcrumbs, no buttons or links, black text on white, A4 margins, and no question split across
  a page break.
- FR-5 (teacher) — From the grading page of a finished attempt a teacher can open a one-page report
  carrying student, class, subject, test title, attempt number, submission date, the score as
  `total_score` / `max_score` plus a percentage, and per question the student's own answer, the
  score earned out of that question's points, and the teacher's comment — plus the overall grade
  comment. An attempt still `in_progress` is refused with a message.
- FR-6 (student) — The parent report carries **no answer key**: no correct option, no correct order,
  no `pairs` map, no `rubric`, no `model_answer`, and no per-answer correct/incorrect marker. It also
  carries no `access_token`. This holds while the test is still `published` and the rest of the
  class is writing.
- FR-8 (student) — A printed shuffle is never the answer order. `ordering` items never print in
  `correct_order_ids` order, and the `matching` bank never prints so that reading it down the page
  answers the left column. A plain seeded shuffle lands on the answer order with probability `1/n!`
  — one in two for the smallest legal matching question — and on paper the whole class holds that
  same sheet, so the guarantee has to be structural, not probabilistic. It holds from three entries
  up. With two there is exactly one order that is not the key, so refusing the key would print its
  reverse every time and a reader who knows the rule takes it bottom-up: the even chance of a plain
  draw is the best available at that size, and the draw is kept. The refusal is a re-draw on a
  derived seed, never a fixed transform of the drawn order — undoing a public transform names the
  key, which measurably beats a blind guess.
- FR-7 (teacher) — The paper copy is reachable from the test tab bar; the answer-key copy only from
  the paper copy; the report only from the attempt's grading page. All three links disappear when
  the page is printed.

## Technical Approach

Nothing new in the § KISS gate sense: no table, no column, no model, no controller, no service, no
gem, no Stimulus controller. Three actions on two existing controllers, four views, one partial, and
one `@media print` section in the stylesheet that is already there.

**Why the browser makes the PDF and no gem does.** `Gemfile.lock` carries no PDF renderer of any
kind. Every candidate costs more than it returns here: `prawn` would mean hand-laying six question
types and embedding a Cyrillic font, since its built-in AFM fonts are Latin-1 only; `wicked_pdf`
depends on the retired `wkhtmltopdf`; `grover` and `puppeteer-ruby` need Chromium inside the Kamal
image, which is the largest single change this feature could make to deployment. A print stylesheet
reaches the same artifact — `Ctrl+P` → *Save as PDF* — through a page the existing test suite can
already assert on. `selenium-webdriver` is in `Gemfile.lock` but only in the `:test` group, so it is
not a production path either.

**Why two routes for the test copy, not one action with a flag.** A single `exams#print` reading
`params[:key]` puts the answer key one mis-defaulted ternary away from the student sheet, in a
template where both branches sit side by side. Two actions rendering two files that share no partial
make the boundary a whole file: `app/views/exams/print.html.erb` never mentions `correct_option_id`,
`pairs`, `rubric` or `model_answer` at all, so a leak there has to be typed deliberately rather than
inverted by accident. `docs/agent-rules.md` § Never leak answer keys calls the student run view "the
only boundary"; this makes the second one shaped the same way.

**Why the report cannot reuse `app/views/attempts/_student_answer.html.erb`.** That partial renders
the key on purpose: for `ordering` it prints the full `question.items` list under
`attempts.grade.correct_order`, and for `matching` it reads `question.pairs` and prints the expected
right item through `attempts.grade.pair_expected`. It is correct for the grading page and wrong for
anything leaving the building, so the report gets `app/views/attempts/_report_answer.html.erb`, which renders the
student's own `payload` mapped through the student-facing readers and stops there.

**Why no new layout.** `app/views/layouts/application.html.erb` is reused for all three pages and
its chrome is hidden by `@media print`. A dedicated print layout was considered and rejected: the
teacher needs the breadcrumbs and a way back on screen, and the chrome that would justify a separate
layout — header, flash, tabs — is exactly what one `@media print` rule removes anyway. There would
be nothing left in the third layout but a `<main>`.

### Affected Areas

- Models: `app/models/question.rb` — add `unaligned_items` and `unaligned_right_items` beside the
  existing shuffle readers, plus one private helper. `why`: the comparison that proves a shuffle is
  not the answer order has to read `correct_order_ids` and `pairs`, and those are exactly the
  readers the print view may never touch. Doing it in the view was the rejected alternative — it
  would put the answer key inside the answer-key boundary to keep the key out of it.
- Controllers: `app/controllers/exams_controller.rb` — add `print` and `print_key`, both on the
  existing `set_exam`. `app/controllers/attempts_controller.rb` — add `report` on the existing
  `set_attempt`, and move `show`'s four ivar assignments into a private `load_attempt_view` both
  actions call, so the report cannot drift from what `show` loads.
- Views: `app/views/exams/print.html.erb` (new), `app/views/exams/print_key.html.erb` (new),
  `app/views/attempts/report.html.erb` (new), `app/views/attempts/_report_answer.html.erb` (new),
  `app/views/exams/_tabs.html.erb` (one tab), `app/views/attempts/show.html.erb` (one link).
  `app/views/questions/_photo.html.erb` is rendered by the two test copies, unchanged.
- Services: none. No new service — nothing here is domain or security logic beyond choosing which
  existing `Question` reader to call, which is a template decision. `Scoring` and `AttemptLifecycle`
  are not touched.
- Jobs: none.
- Stylesheet: `app/assets/tailwind/application.css` — one `@media print` section appended, beside
  the existing `@media (prefers-reduced-motion: reduce)` block. No new stylesheet file; Propshaft
  builds this one and both layouts already link it as `:app`.
- Routes: `config/routes.rb` — two members on the `resources :exams, path: "tests", as: :tests`
  block, one on `resources :attempts`.
- Locales: `config/locales/uk.yml`.
- Tests: `test/integration/exam_print_test.rb` (new),
  `test/integration/attempt_report_test.rb` (new),
  `test/integration/answer_key_leak_test.rb`, `test/integration/exam_tabs_test.rb`.

### Database Changes

`N/A — no schema change.` Everything printed already exists: `questions.prompt` and
`questions.config`, `answers.payload` / `auto_score` / `teacher_score` / `teacher_comment`,
`grades.total_score` / `max_score` / `finalized_by_teacher` / `teacher_comment`, and the
`students`, `subjects`, `class_groups` names reached through existing associations.

### Routes

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|
| GET | `/tests/:id/print` | `print_test_path` | `exams#print` | teacher |
| GET | `/tests/:id/print_key` | `print_key_test_path` | `exams#print_key` | teacher |
| GET | `/attempts/:id/report` | `report_attempt_path` | `attempts#report` | teacher |

Helpers follow the `/tests` ↔ `Exam` split from `docs/agent-rules.md` § Domain and naming: the
top-level exam block carries `as: :tests`, so both new members are `*_test_path`, matching the
`publish_/close_/results_/live_test_path` already there. `resources :attempts, only: %i[show update]`
gains a `member do get :report end`.

All three are HTML pages rendered by the server. No JSON, no new format, no `respond_to`.

### Views & Hotwire

- **Views/partials**: the four new files above. Each of the three pages is one flowing document
  region, not a Turbo Frame — printing a frame prints whatever the frame last loaded, and none of
  this content updates in place.
- **Stimulus**: none added, and none of the existing eight (`autosave`, `autosubmit`, `countdown`,
  `clipboard`, `ordering`, `live_board`, `dismiss`, `hello`) is used. The "Друкувати" control is a
  plain link with `onclick`-free markup — a `<button>` calling `window.print()` would be the ninth
  controller for one line; the teacher's own `Ctrl+P` is the documented path and the button is
  a convenience the PRD leaves out. See § Out of Scope.
- **Turbo targets**: none. Nothing on these pages is a broadcast target.
- **Broadcasts**: none. Printing is a read; no attempt status or answer content moves, so neither
  `LiveBoard` nor `GradeLive` fires.
- **New gem**: none — see § Technical Approach.
- **Print classes**: `print-sheet` on each page root, `print-question` on each question block,
  `no-print` on every on-screen control, `answer-lines` on the ruled writing space. These are the
  hooks the `@media print` section keys on; they carry no styling of their own outside print, so
  markup and stylesheet can be asserted separately.

## Security

- **Student-facing output** — **yes, twice, and this is the whole risk of the feature.**

  `app/views/exams/print.html.erb` is a new answer-key boundary: paper reaches students. Its
  allowlist, per question type, is exactly what `app/views/take/runs/show.html.erb` sends today —
  `prompt`, `points`, the type label, the photo, and:
  - `mcq` → `student_facing_options`, `id` and `text` only. Never `is_correct`, and no box is
    pre-ticked.
  - `ordering` → `shuffled_items(@exam.id)`. Never `items`, whose stored order **is**
    `correct_order_ids`.
  - `matching` → `student_facing_left` and `shuffled_right_items(@exam.id)`. Never `pairs`.
  - `source` → `source_text` and the prompt. Never `rubric` or `model_answer`, which live in the
    same `config` hash.
  - `short_text` / `open` → prompt only; no `config` is read.

  `app/views/attempts/_report_answer.html.erb` is the second: it renders the student's own
  `answers.payload` — `option_id`, `order_ids`, `pairs`, `text` — mapped to display text through
  `student_facing_options`, `student_facing_items`, `student_facing_left` and
  `student_facing_right`. A student's own `payload["pairs"]` is their answer, not the key
  (`docs/agent-rules.md` says so explicitly), and mapping it through the stripped readers means the
  correct mapping is never fetched to compare against. It renders no correctness marker at all.

  `app/views/exams/print_key.html.erb` is deliberately the opposite and is teacher-only: it reads
  `correct_option_id`, `correct_order_ids`, `pairs`, `rubric` and `model_answer`. It is behind
  `require_authentication` and `Current.user.exams.find`, is linked only from the paper copy's own
  page, and is never rendered by a `Take::` controller.

  No new question type is added, so the six in `docs/agent-rules.md` § Domain and naming are
  unchanged — but two new student-facing surfaces are, and both get a case in
  `test/integration/answer_key_leak_test.rb` (FR-2, FR-6).

  **Seed divergence, stated rather than assumed.** § Never leak answer keys says to pass
  `@attempt.id` as the shuffle seed and warns that `question.id` would give a whole class the same
  order. A blank photocopied sheet has no attempt and is one order by definition — that is what
  "one blank per test" means — so it passes `@exam.id`. `Question#stable_seed` hashes
  `"#{question.id}:#{seed}:#{suffix}"`, so each question still shuffles independently, and the run
  page keeps passing `@attempt.id` unchanged. See § Open Questions.

- **Teacher data** — yes, read only. `exams#print` and `exams#print_key` reuse the existing
  `set_exam` (`Current.user.exams.find(params[:id])`); `attempts#report` reuses the existing
  `set_attempt` ownership join
  (`Attempt.joins(assignment: :exam).where(exams: { teacher_id: Current.user.id })`). No bare-id
  load is introduced, and a request from another teacher raises `RecordNotFound` → 404.

- **Unauthenticated `Take::`** — `N/A` — no `Take::` action is added or changed, no view under
  `app/views/take/` is touched, and no print route is reachable without a session. No `Current.user`
  reaches `app/controllers/take/`.

- **Assignment tokens** — yes, by omission, and this is the one that needs an assertion. The report
  is built from an `Attempt`, which reaches `assignment.access_token` in one hop, and it is a
  document that goes home in a schoolbag. No template renders it; FR-6 asserts the token string is
  absent from the report body, and the test fails if it is ever added. Neither test copy touches
  `assignments` at all. Nothing here writes a log line, an export file or a fixture, and `/t/:token`
  is untouched.

- **Params** — yes, one per route, and all three are `:id`, consumed by finders that already exist.
  No new `permit` list, no new attribute write, nothing reaches `to_unsafe_h`. All three actions are
  GET and write nothing.

- **Broadcasts and jobs** — `N/A` — nothing is enqueued and nothing is broadcast. These are
  synchronous reads answering the request that made them, so no teacher stream can reach a student.

Every "yes" above becomes a test — see § Testing Strategy.

## Localization

| Key | Ukrainian text |
|---|---|
| `common.print` | Друкувати |
| `exams.show.print` | Друк |
| `exams.print.title` | Друк: %{title} |
| `exams.print.hint` | Роздрукуйте цей аркуш і роздайте учням. Правильних відповідей тут немає. |
| `exams.print.name_field` | Ім’я |
| `exams.print.class_field` | Клас |
| `exams.print.date_field` | Дата |
| `exams.print.score_field` | Бал |
| `exams.print.answer_label` | Відповідь |
| `exams.print.order_hint` | Проставте номери від 1 до %{count} у клітинках. |
| `exams.print.matching_bank` | Варіанти відповідностей |
| `exams.print.matching_hint` | Впишіть літеру потрібного варіанта поруч з кожним фактом. |
| `exams.print.key_link` | Аркуш з відповідями |
| `exams.print_key.title` | Відповіді: %{title} |
| `exams.print_key.heading` | Аркуш з відповідями |
| `exams.print_key.warning` | Лише для вчителя. Не роздавайте цей аркуш учням. |
| `exams.print_key.pairs` | Пари |
| `exams.print_key.sheet_link` | Аркуш для учня |
| `attempts.show.report` | Звіт для батьків |
| `attempts.report.title` | Звіт: %{name} |
| `attempts.report.heading` | Звіт про виконання тесту |
| `attempts.report.class_group` | Клас |
| `attempts.report.subject` | Предмет |
| `attempts.report.date` | Дата |
| `attempts.report.total` | Підсумковий бал |
| `attempts.report.earned` | %{score} з %{max} |
| `attempts.report.teacher_comment` | Коментар учителя |
| `attempts.report.provisional` | Оцінку ще не затверджено. |
| `attempts.flash.report_in_progress` | Звіт можна надрукувати після того, як учень здасть роботу. |

Reused, not re-added: `t("question_types.<type>")`, `t("take.type_hint.<type>")`,
`t("exams.points", count:)`, `t("exams.points_short", count:)`, `t("exams.show.correct")`,
`t("exams.show.rubric")`, `t("exams.show.model_answer")`, `t("exams.show.tabs_label")`,
`t("take.source.label")`, `t("attempts.grade.student_answer")`, `t("attempts.grade.no_answer")`,
`t("attempts.grade.correct_order")`, `t("attempts.grade.attempt", n:)`, `t("attempts.history.test")`,
`t("exams.assign.student")`, `t("subjects.stats.percent", value:)`, `t("common.dash")`.

No bare literals in ERB, controllers or flash messages. `bin/ci` greps `app/` for Cyrillic, so a
stray string fails the build rather than shipping.

## UI/UX — User Flow

1. Teacher opens a test. The **tab bar** (`app/views/exams/_tabs.html.erb`) now carries "Друк" beside
   Overview / Налаштування / Призначити, for every status — the paper backup is most useful before
   the test is published, so it is not gated the way Онлайн-табло and Результати are.
2. `print_test_path` renders inside the normal app shell. The **document region** is the sheet:
   class · subject · title, blank Ім’я / Клас / Дата / Бал lines, total points, then each question
   with hand-writing space. Above it, in a `no-print` **action strip**, sit the hint, "Друкувати"
   and "Аркуш з відповідями".
3. Teacher prints. The header, breadcrumbs, tab bar and the whole action strip vanish; what remains
   is the sheet, A4, black on white, questions unbroken across pages.
4. "Аркуш з відповідями" opens `print_key_test_path` — same document region, answers filled in, a
   `no-print` warning at the top, and a link back to the student sheet.
5. After grading, the teacher is already on `attempt_path(@attempt)`. Its **action row** gains "Звіт
   для батьків" beside Зберегти / Затвердити, shown only once the attempt is finished.
6. `report_attempt_path` renders the report: identity block, score block, one row per question with
   the student's answer and what it earned, the overall comment, and — when the grade is not
   finalized — the `attempts.report.provisional` note. Teacher prints and hands it over.
7. A teacher who reaches `report_attempt_path` for an attempt still `in_progress` is redirected to
   the grading page with `attempts.flash.report_in_progress`.

## Edge Cases

- **Test with no questions** (a fresh `draft`). Both copies render the header and an empty question
  list rather than 404ing — the blank name/date sheet is still a usable thing to photocopy.
- **Exam status.** All three pages work for `draft`, `published` and `closed`. Printing is a read;
  nothing about it depends on the lifecycle, and gating the paper backup on `published` would deny
  it exactly when a teacher is preparing.
- **Two-entry matching bank.** FR-8 does not cover it, by design — see § Open Questions. The plain
  even chance is kept rather than replaced by a certain reverse.
- **Matching bank colliding with the answer order.** `matching_has_pairs` allows two pairs, where a
  plain shuffle prints the bank in answer order half the time — a student lettering straight down the
  left column would score full marks. FR-8 removes this rather than documenting it.
- **Ordering shuffle colliding with the stored order.** With three items there is a 1-in-6 chance
  `shuffled_items(@exam.id)` lands on `correct_order_ids`. On paper this is far weaker than the same
  collision online: the student writes numbers into empty boxes, so a coincidentally-correct listing
  reads as an unordered list and submits nothing. It is not silently correct the way an untouched
  drag list is. Accepted, consistent with the run page, and noted in § Open Questions.
- **Question with a photo.** `app/views/questions/_photo.html.erb` renders on both test copies; the print
  rules keep it inside its `print-question` block so a page break cannot separate it from its
  prompt.
- **Very long `source` text.** The run page clamps it with `max-h-80`; on paper it must not scroll,
  so the print sheet renders it in full and lets it flow across pages.
- **Attempt in progress** → report refused (FR-5). **Expired attempt** → report renders; it is
  graded like any other, and the status is shown. **Attempt swept by `ExpireOverdueAttemptsJob` or
  `ExpireAttemptJob`** → same, no special case; the sweep only moves status.
- **Attempt with no `grade` row** (submitted, teacher has not opened it). The score block renders
  `common.dash` over `Exam#max_score` and the `provisional` note shows.
- **Grade not finalized.** Renders with `attempts.report.provisional`; the numbers are
  `Scoring.partial_total`'s last write, which is what the grading page shows too.
- **Question a teacher has not scored yet** (`short_text`, `open`, `source` with no
  `teacher_score`). `Answer#effective_score` returns `nil`; the row prints `common.dash` out of the
  question's points rather than a misleading zero.
- **Unanswered question.** `attempts.grade.no_answer`, reused.
- **A two-option MCQ scored 0.** The report shows the student's choice and `0`, which for two
  options implies the other one. That is inherent to any report carrying per-question scores, is not
  an answer key reaching a student, and stays under the teacher's control over who gets the sheet.
  Recorded here so a reviewer sees it was weighed, not missed.
- **Token revoked or regenerated.** Irrelevant to all three pages — none reads `assignments`, and the
  report is keyed on the attempt.
- **Large class.** These are per-test and per-attempt pages; neither loads a collection that grows
  with the roster.

## Out of Scope

- A server-generated `.pdf` file, and every gem that would take: `prawn`, `wicked_pdf`, `grover`,
  `puppeteer-ruby`. If the browser path proves insufficient, that is its own PRD with its own
  Dockerfile change.
- Batch printing — all reports for a class, or all students' sheets, in one document.
- Per-student personalized sheets: name pre-filled, shuffles seeded by `assignment.id` so neighbours
  differ. Explicitly rejected in favour of one photocopiable blank.
- The subject-wide term summary for a student. `Subject#student_stat_rows` already computes it and
  `app/views/subjects/stats.html.erb` already shows it; turning that into a printed tabel is a different
  document.
- A report link on `app/views/exams/results.html.erb`. The grading page is the one entry point for now.
- A `window.print()` button backed by a Stimulus controller. `Ctrl+P` is the documented path.
- Emailing or otherwise delivering reports; there is no student or parent contact flow in this app.
- Any student-facing print route. Nothing under `/t/:token` gains a printable page.
- Marking answers correct or incorrect on the parent report, in any form.
- Changing what `app/views/attempts/_student_answer.html.erb` renders. It stays as it is.

## Open Questions

- Should a `matching` question be required to carry more right items than pairs, or at least three
  pairs? — **non-blocking, but the sharpest remaining edge.** FR-8 cannot protect a two-entry bank:
  the security review that produced FR-8 also showed that refusing the key there prints its reverse
  every time, so the code deliberately keeps the even chance instead. `matching_has_pairs` allows two
  pairs, so a teacher can still author a printed question that a coin-flip reads correctly. Widening
  the validation, or letting the bank carry distractors, would close it — both change what a teacher
  may author, so neither belongs in this PRD.
- Should `docs/agent-rules.md` § Never leak answer keys gain a sentence covering the non-attempt
  seed? — **non-blocking.** The rule as written says "always pass `@attempt.id` explicitly", which
  is right for the run page and unsatisfiable for a blank sheet. The PRD's answer is `@exam.id` with
  the reasoning above, but that section is the contract and only the developer should widen it.
  Until then a reader could fairly call the print sheet a divergence.
- Should the printed sheet re-seed when `shuffled_items(@exam.id)` matches `correct_order_ids`? —
  **non-blocking.** It would be a small loop in `Question`, and it would make the paper sheet
  stricter than the live run page, which does not do it. Left out for consistency; the § Edge Cases
  argument is that the collision is much less harmful on paper.
- Should the answer-key copy show each question's `points` breakdown for `matching`, where scoring
  is partial (`points × correct / pairs`)? — **non-blocking.** The pairs are listed either way; only
  the arithmetic hint is missing.

## Testing Strategy

- `test/integration/exam_print_test.rb` — **new**; the pattern to copy is
  `test/integration/assignments_manage_test.rb`. Proves: the paper copy renders for `draft`,
  `published` and `closed`; every question type produces its blank answer space; ordering items come
  out in `shuffled_items(exam.id)` order and matching right items in `shuffled_right_items(exam.id)`
  order; the answer-key copy marks the correct option, the `correct_order_ids` order, every pair,
  the rubric and the model answer; both 404 for another teacher; both carry the `print-sheet`,
  `print-question` and `no-print` hooks; a test with no questions still renders.
- `test/integration/answer_key_leak_test.rb` — **extend**, two cases. One renders
  `print_test_path` as the owning teacher and runs the file's existing `assert_no_answer_key`, plus
  the visible-content assertions that stop an empty body from passing vacuously, plus that the
  sheet's ordering ids are not `correct_order_ids`. One renders `report_attempt_path` for a
  submitted attempt and runs the same helper, and additionally asserts the body carries neither
  `t("attempts.grade.correct_order")` nor the expected-pair text nor `assignment.access_token`.
  These are the tests that fail if `_report_answer` is ever swapped for `_student_answer`, or if a
  key reader is added to `app/views/exams/print.html.erb`.
- `test/integration/attempt_report_test.rb` — **new**. Proves: the report renders the identity and
  score blocks and one row per question with the student's answer and `effective_score` out of
  `question.points`; an unscored teacher-graded answer prints `common.dash`, not `0`; an unfinalized
  grade carries `attempts.report.provisional`; an attempt with no `grade` row still renders; an
  `in_progress` attempt redirects with `attempts.flash.report_in_progress`; another teacher's
  attempt 404s; the grading page shows the report link only once the attempt is finished.
- `test/integration/exam_tabs_test.rb` — **extend**: the tab bar carries `print_test_path` for
  `draft`, `published` and `closed`, alongside the existing Онлайн-табло / Результати gating.
- `test/integration/mvp_flow_test.rb` — **not** extended. The teacher → assign → take → grade spine
  is unchanged; printing sits beside it, not in it.
- `test/integration/n_plus_one_test.rb` — **not** extended. `exams#print` and `exams#print_key` load
  `@exam.questions.with_attached_photo`, the same single collection `exams#show` already loads and
  the file already covers; `attempts#report` reuses `set_attempt`, whose
  `includes(:answers, :grade, assignment: [:student, { exam: :questions }])` is unchanged. Neither
  adds a collection that grows with the class.
- `test/models/`, `test/services/` — **not** extended. No model or service behaviour changes.

**What has no automated coverage, stated plainly.** The `@media print` rules themselves. There are
no system tests in this repo (`docs/agent-rules.md` § Quality), and a stylesheet cannot be asserted
from an integration test. The tests assert the markup hooks the rules key on — `print-sheet`,
`print-question`, `no-print` — so a template that stops emitting them fails; whether the resulting
page break lands correctly is verified by eye in a browser print preview, the same way autosave and
drag-to-reorder are.

Quality loop and commands: `docs/agent-rules.md` § Quality.

## Implementation Tasks

One commit per task.

- [x] FR-8 — Add `Question#unaligned_items` and `Question#unaligned_right_items`, which return a
      seeded shuffle that is never the recorded answer order — done when: for every seed in a wide
      range, `unaligned_items` never equals `correct_order_ids` and the first `left_items.size`
      entries of `unaligned_right_items` never equal the correct right-id sequence, both are stable
      across repeated calls for one seed, a question whose plain shuffle *is* the answer order still
      returns an unaligned list, repeated re-draws do not all land on one order, a bank longer than
      its left column is still covered, and a two-entry bank still returns both of its orders —
      proof: `test/models/question_test.rb`
- [x] FR-1, FR-2, FR-4 — Add the `print` member route, `ExamsController#print` on the existing
      `set_exam`, `app/views/exams/print.html.erb`, the `exams.print.*` and `common.print` keys, and
      the `@media print` section in `app/assets/tailwind/application.css` — done when: a GET by the
      owning teacher on a `draft`, a `published` and a `closed` test renders every question in
      position order with its number, type label, points and prompt; `mcq` renders unticked boxes
      from `student_facing_options`, `ordering` renders `unaligned_items(@exam.id)` each with an
      empty position box, `matching` renders `student_facing_left` with a blank plus a lettered bank
      from `unaligned_right_items(@exam.id)`, `short_text` / `open` / `source` render ruled
      `answer-lines` and `source` also its `source_text`; the page root carries `print-sheet`, every
      question block `print-question` and every control `no-print`; a test with no questions renders
      the header alone; and a GET by another teacher 404s — proof:
      `test/integration/exam_print_test.rb`
- [x] FR-2 — Extend `test/integration/answer_key_leak_test.rb` with the printed student sheet —
      done when: the sheet rendered for the owning teacher passes the file's `assert_no_answer_key`,
      carries the option, left-item and source text so an empty render cannot pass vacuously, and
      lists its ordering items in an order that is not `correct_order_ids` — proof:
      `test/integration/answer_key_leak_test.rb`
- [x] FR-3 — Add the `print_key` member route, `ExamsController#print_key`,
      `app/views/exams/print_key.html.erb` and the `exams.print_key.*` keys — done when: the key
      sheet marks the correct `mcq` option with `exams.show.correct`, lists `ordering` items in
      `correct_order_ids` order, lists every `pairs` entry as left → right, prints `rubric` and
      `model_answer` under the existing `exams.show.*` labels, carries the `no-print` teacher-only
      warning, and a GET by another teacher 404s — proof: `test/integration/exam_print_test.rb`
- [x] FR-5, FR-4 — Add the `report` member route on `resources :attempts`,
      `AttemptsController#report` sharing `show`'s loading through a new private
      `load_attempt_view`, `app/views/attempts/report.html.erb`,
      `app/views/attempts/_report_answer.html.erb` and the `attempts.report.*` and
      `attempts.flash.report_in_progress` keys — done when: a GET by the owning teacher on a
      submitted attempt renders student, class, subject, test, attempt number, submitted date,
      `total_score` / `max_score` with a percentage, and per question the student's own answer,
      `Answer#effective_score` out of `question.points`, and the answer's teacher comment, plus the
      overall grade comment; an unscored teacher-graded answer prints `common.dash` rather than `0`;
      an attempt with no `grade` row and an unfinalized grade both render with
      `attempts.report.provisional`; a GET on an `in_progress` attempt redirects with
      `attempts.flash.report_in_progress`; and another teacher's attempt 404s — proof:
      `test/integration/attempt_report_test.rb`
- [x] FR-6 — Extend `test/integration/answer_key_leak_test.rb` with the parent report — done when:
      the report rendered for a submitted attempt passes `assert_no_answer_key`, carries the
      student's own answer text so an empty render cannot pass vacuously, contains neither the
      expected-pair text `t("attempts.grade.pair_expected", …)` nor the assignment's
      `access_token`, and renders the student's own order and mapping rather than the stored
      ones — proof: `test/integration/answer_key_leak_test.rb`

      Do **not** refute `t("attempts.grade.correct_order")` against the whole body: it is
      byte-identical to `t("question_types.ordering")`, which the type chip prints, so the
      assertion fails on any report carrying an ordering question. Scope that property to the
      answer block instead, by comparing it to the student's `order_ids`.
- [x] FR-7 — Add the "Друк" tab to `app/views/exams/_tabs.html.erb`, the `exams.print_key.sheet_link`
      and `exams.print.key_link` cross-links on the two test copies, and the "Звіт для батьків" link
      on `app/views/attempts/show.html.erb`, every one of them `no-print` — done when: the tab bar
      links to `print_test_path` for `draft`, `published` and `closed`; the paper copy links to
      `print_key_test_path` and the key copy back to `print_test_path`; and the grading page links
      to `report_attempt_path` for a finished attempt and renders no such link while the attempt is
      `in_progress` — proof: `test/integration/exam_tabs_test.rb`,
      `test/integration/attempt_report_test.rb`
