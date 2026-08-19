# Export grades to CSV

## Overview

A teacher can download the table they already see on a test’s results page and on a subject’s stats page as a CSV, and paste it into the class journal. Students never see this. There is no export in `app/` or `lib/` today — this is that first, smallest download.

## Requirements

### Functional

- FR-1 (teacher) — The owning teacher’s GET of `results_test_path(exam, format: :csv)` returns 200 with a semicolon-separated UTF-8 CSV (leading BOM). One row per assignment, same set and name order as `ExamsController#results` (`app/controllers/exams_controller.rb:52`). Columns: student name, latest-attempt status (`statuses.*`, or `statuses.not_started` when there is no attempt), started_at, submitted_at, `grades.total_score`, `grades.max_score`. Latest attempt only (`Assignment#latest_attempt`). Missing numbers and timestamps are empty cells, not `common.dash`. HTML `results_test_path` is unchanged.
- FR-2 (teacher) — The owning teacher’s GET of `stats_subject_path(subject, format: :csv)` returns 200 with the same encoding. One row per `Subject#student_stat_rows` entry (`app/models/subject.rb:9`), same students and order as the HTML table. Columns: student name, finished/assigned (`subjects.stats.progress` when `assigned > 0`, else empty), `average_percent` as the integer already computed (no `%`), last_activity_at. Missing numbers and timestamps are empty cells.
- FR-3 (teacher) — `app/views/exams/results.html.erb` and `app/views/subjects/stats.html.erb` each show one download link to that page’s `.csv` path, labelled `common.export_csv`, class `btn_secondary`, `data-turbo="false"`. The link is present in the empty state as well as when the table has rows.
- FR-4 (teacher) — Neither CSV header nor body contains `access_token`, a `/t/` path, an assignment token value, or `students.email`.
- FR-5 (teacher) — A GET of either CSV by another teacher is 404 (`Current.user.exams.find` / `Current.user.subjects.find`). A signed-out GET redirects to `new_session_path`.

## Technical Approach

Nothing new in the KISS-gate sense: no table, column, model, controller, service, gem, or Stimulus controller.

CSV is `respond_to` + `send_data` on the two actions that already load the rows. `require "csv"` (Ruby stdlib; `Gemfile.lock` has no `csv` gem; do not add one). `format.csv` does not need a new `config/routes.rb` entry — `get :results` and `get :stats` already accept a format.

**Why no `Exam#results_rows` (skill example) and no new service.** The HTML already walks `@assignments` / `@stat_rows` with `latest_attempt` and `grade`. A second row builder on the model or a `JournalCsv` / `LiveBoard`-style object would be another way to produce the same table. `LiveBoard#snapshot` (`app/services/live_board.rb:16`) was considered and rejected: it sorts by board status, does not load `grades`, and is the live-board payload, not a journal file. `Subject#student_stat_rows` already is the stats table.

**Why `ApplicationController#send_csv(filename, headers, rows)` rather than two inlined `CSV.generate`s or a `.csv.erb`.** Both downloads must share BOM + `col_sep: ";"` + `text/csv; charset=utf-8` or Excel on Windows mangles Ukrainian names. That plumbing is not domain logic, so it is not a service under `app/services/`. A template still needs the controller to set `Content-Disposition`; `send_data` does both. Signature only: `send_csv(filename, headers, rows)`.

**Why `;` and a BOM, not comma CSV.** The file is for the class journal in Excel/LibreOffice with `config.time_zone = "Kyiv"` (`config/application.rb:23`). UA Excel treats comma as the decimal mark; a leading UTF-8 BOM is what makes Cyrillic names readable on Windows. `CSV.generate` quotes a name that itself contains `;`.

**Why `data-turbo="false"`, not a new Stimulus controller.** Turbo Drive would otherwise replace the page with the CSV body. The existing Stimulus set (`autosave`, `autosubmit`, `countdown`, `clipboard`, `ordering`, `live_board`, `dismiss`) has nothing that starts a file download.

Score cells: `total_score` / `max_score` via BigDecimal `to_s("F")` so the cell is `1.0`, not `0.1E1`. Dates: the same `l(time, format: :short)` the HTML already uses.

### Affected Areas

- Controllers: `app/controllers/application_controller.rb` — add `send_csv`. `app/controllers/exams_controller.rb` — `respond_to` in `#results`. `app/controllers/subjects_controller.rb` — `respond_to` in `#stats`.
- Views: `app/views/exams/results.html.erb`, `app/views/subjects/stats.html.erb` — one link each. Region: the heading row above the table / empty state. Not a Turbo Frame (neither page has one).
- Models: none. Reuse `Assignment#latest_attempt` (`app/models/assignment.rb:49`) and `Subject#student_stat_rows`.
- Services: none.
- Jobs: none.
- Locales: `config/locales/uk.yml`.
- Tests: `test/integration/grades_export_test.rb` (new). Extend `test/integration/n_plus_one_test.rb` (the results and stats examples already on that file). Do not extend `test/integration/mvp_flow_test.rb` — the teacher → assign → take → grade spine does not change.

### Database Changes

`N/A — no schema change.` Reads `assignments`, `attempts`, `grades`, `students` as they stand (`db/schema.rb`).

### Routes

No new route entry. Format added on the existing member actions:

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|
| GET | `/tests/:id/results.csv` | `results_test_path(format: :csv)` | `exams#results` | authenticated teacher |
| GET | `/subjects/:id/stats.csv` | `stats_subject_path(format: :csv)` | `subjects#stats` | authenticated teacher |

Helpers verified against `config/routes.rb` (`as: :tests` member `get :results`; `subjects` member `get :stats`). Not JSON — a file download.

### Views & Hotwire

- **Views/partials**: `app/views/exams/results.html.erb` — button above the table/empty copy, same flex heading pattern as `app/views/subjects/show.html.erb:4-7`. `app/views/subjects/stats.html.erb` — button on the existing `h2` block (`:4-8`).
- **Stimulus**: none.
- **Turbo targets**: none. Links set `data-turbo="false"` so Turbo Drive does not consume the CSV.
- **Broadcasts**: none. No `LiveBoard` / `GradeLive`.
- **New gem**: none.

## Security

- **Student-facing output** — N/A — teacher-only download. No `Take::` view, no question config, no new case in `test/integration/answer_key_leak_test.rb`.
- **Teacher data** — yes. Results reuses `Current.user.exams.find(params[:id])` (`exams_controller.rb:69`) and rows from `@exam.assignments`. Stats reuses `Current.user.subjects.find(params[:id])` (`subjects_controller.rb:74`) and `Subject#student_stat_rows` (class students through `class_group`, exams through the subject). No bare-id load.
- **Unauthenticated `Take::`** — N/A — no `Take::` action added or changed.
- **Assignment tokens** — yes, by omission. Assignments are loaded (they carry `access_token`) but the CSV column list is an allowlist of name, status, timestamps, and scores. Proven by FR-4: the test fails if `access_token`, a token value, `/t/`, or `students.email` appears.
- **Params** — yes: `format`. Constrained to `:csv` by `respond_to`. No new `permit` list.
- **Broadcasts and jobs** — N/A — synchronous `send_data`, nothing enqueued or broadcast.

## Localization

| Key | Ukrainian text |
|---|---|
| `common.export_csv` | Завантажити CSV |
| `exams.results.max_score` | Максимум |

CSV headers otherwise reuse keys the HTML tables already use: `exams.assign.student`, `exams.results.latest_status`, `attempts.history.started`, `exams.results.submitted`, `exams.results.score`, `subjects.stats.student`, `subjects.stats.tests`, `subjects.stats.average`, `subjects.stats.last`, `subjects.stats.progress`, `statuses.*`. No Cyrillic literals in `app/` (CI greps for them).

## UI/UX — User Flow

1. Teacher opens Результати (`results_test_path`) → heading row shows **Завантажити CSV** → click (full navigation, not a frame) → browser downloads `<exam title>.csv`.
2. Teacher opens Успішність учнів (`stats_subject_path`) → same control → `<subject name>.csv`.

## Edge Cases

- No assignments / no class students: 200, header row only (and name rows on stats when the class has students but no published/closed exams — that is what `student_stat_rows` already returns).
- Several attempts: one CSV row, `latest_attempt`, matching `test/integration/n_plus_one_test.rb:22`.
- No `grades` row, or `total_score` nil (teacher-scored, not yet marked): score cells empty; `max_score` emitted only when a grade exists.
- `in_progress` / `expired` / `submitted` / `abandoned`: status from the latest attempt; dates and scores empty when absent.
- Revoked assignment: included on results (the HTML has no revoked filter); excluded from stats counts because `student_stat_rows` skips `assignment.revoked?`.
- Archived student: results if still assigned; stats only `students.active`.
- Draft exam: `#results` is not status-gated today; CSV follows that. The results tab stays hidden for drafts (`app/views/exams/_tabs.html.erb:5`).
- Student name containing `;`: quoted by `CSV.generate`, still one column.
- Large class: same preload as HTML — `n_plus_one_test.rb` must cover `format: :csv` on both actions.

## Out of Scope

- Student × exam matrix (one column per test on the stats download). Stats CSV is the table already on that page, not a pivot.
- `.xlsx`, Google Sheets, email, or a background job.
- Converting points to a 12-point journal mark.
- Per-question breakdown, attempt history rows, or `finalized_by_teacher` as a column.
- Changing scoring, finalization, or which attempt is “latest”.
- Student-facing download, or any `Take::` change.
- A new route, controller, service, gem, or Stimulus controller.
- Exporting assignment links or tokens.

## Testing Strategy

- `test/integration/grades_export_test.rb` (new) — owner CSV bodies and headers, empty file, latest-attempt-only, semicolon + BOM, quoted `;` in a name, other-teacher 404, signed-out redirect, no token/email/`/t/`, both HTML pages render the turbo-disabled link. Pattern: `test/integration/assignments_manage_test.rb`.
- `test/integration/n_plus_one_test.rb` — extend the existing results (`:12`) and subject stats (`:79`) examples to GET `format: :csv` with the same per-record assertions (`attempts`/`grades`/`assignments`).
- `test/integration/mvp_flow_test.rb` — do not extend; the spine is unchanged.
- `test/integration/answer_key_leak_test.rb` — do not extend; no student-facing field.

Quality loop: `docs/agent-rules.md` § Quality.

## Implementation Tasks

- [x] FR-1 — Add `ApplicationController#send_csv(filename, headers, rows)` and `respond_to` `:csv` on `ExamsController#results` (reuse the existing `@assignments` preload; add `exams.results.max_score` in `uk.yml`) — done when: owner GET `results_test_path(format: :csv)` is 200, body starts with a UTF-8 BOM, `CSV.parse(..., col_sep: ";")` has one data row per assignment ordered by student name with score/max matching the latest attempt’s grade (empty when missing), a name containing `;` stays one column, HTML `results_test_path` is still 200, and the CSV GET does not query attempts or grades per assignment — proof: `test/integration/grades_export_test.rb`, `test/integration/n_plus_one_test.rb`
- [x] FR-2 — Add `respond_to` `:csv` on `SubjectsController#stats` via `send_csv` and `@stat_rows` — done when: owner GET `stats_subject_path(format: :csv)` is 200 with the same BOM/semicolon rules, rows match `student_stat_rows` (name, progress, integer percent, last activity; empties as specified), HTML stats is still 200, and the CSV GET does not query assignments per exam or attempts/grades per assignment — proof: `test/integration/grades_export_test.rb`, `test/integration/n_plus_one_test.rb`
- [x] FR-5 — Cover ownership and session on both CSV endpoints — done when: `users(:two)` gets 404 from both `.csv` paths and a signed-out GET of either redirects to `new_session_path` — proof: `test/integration/grades_export_test.rb`
- [x] FR-4 — Assert the secrets stay out of both files — done when: the test fails if `access_token`, the assignment’s token value, `/t/`, or the student’s email is added to a header or row of either CSV — proof: `test/integration/grades_export_test.rb`
- [ ] FR-3 — Add `common.export_csv` and the two download links (`btn_secondary`, `data-turbo="false"`), including on the empty state — done when: each HTML page contains `a[href="<csv path>"][data-turbo="false"]` with the Ukrainian label — proof: `test/integration/grades_export_test.rb`
