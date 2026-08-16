---
name: prd
description: Write a product requirements document for a school-app feature before any code is written. Use when the user says /prd, asks for a PRD, spec, feature plan, or scoping doc; or when a change would touch db/schema.rb, add a route or controller action, change a question type or scoring rule, touch both a teacher-facing and a student-facing path, or need more than one commit to keep the suite green. Not for a change that fits in one commit, and not for executing a PRD that already exists — that is /implement-prd. Produces prd/_to_refine/<kebab-name>/project.md whose Implementation Tasks are the contract handed to /implement-prd.
---

# PRD

Turn a feature request into `prd/_to_refine/<kebab-name>/project.md`: a spec whose task list
`/implement-prd` can execute one commit at a time.

`docs/agent-rules.md` is the canonical contract for naming, style, security, quality, and git. This skill
does not restate those rules. Where a section below asks a question, answer it *against*
`docs/agent-rules.md` — state how the feature complies, do not copy the rule in. If this file and
`docs/agent-rules.md` disagree, `docs/agent-rules.md` wins.

## Invocation

- `/prd <feature description>` — enough to start. Research, then write.
- `/prd` — no description. Ask first, then research, then write.

Ask vs inspect: `docs/agent-rules.md` § When to ask vs inspect. Applied here — the question comes *before* the
PRD exists, not while it is being written.

## Procedure

1. **Gather.** Description supplied and unambiguous: go to step 2. No description, or the request turns
   on something `docs/agent-rules.md` § When to ask vs inspect flags as ask-first: ask up to three questions covering scope,
   the teacher-side and student-side story, and what is explicitly out — then continue.
2. **Research.** Read before writing. At minimum: `db/schema.rb`, `config/routes.rb`, the controllers
   and views you would touch, `app/services/`, `config/locales/uk.yml`, and the test file covering the
   controller or service you will touch (`test/integration/`, `test/services/`, `test/models/`); if
   none exists, `test/integration/mvp_flow_test.rb`. Cite real files — no invented ones.
3. **Name.** Kebab-case, derived from the feature: `export-class-results`, `numeric-question-type`.
4. **Create** `prd/_to_refine/<kebab-name>/`. If that name already exists in any of the three
   stages, stop and ask — do not overwrite a PRD.
5. **Write** `project.md` from the template below, in order. A section with nothing in it is omitted —
   except § Security and § Out of Scope, which always appear even when the answer is `N/A — <why>`.
   Do not write code in the PRD beyond a signature or a route line. It is a spec, not a patch.
6. **Self-check.** Confirm and state each, before reporting. Any "no" is fixed, not noted.
   - a. Every path named in the PRD exists on disk, or is marked new.
   - b. Every new table, column, service, model, controller, gem, or Stimulus controller carries a
     `why` that names a rejected alternative (§ KISS gate).
   - c. Every `FR-n` appears in at least one task, and every task cites an `FR-n`. State the count:
     `12 requirements → 9 tasks, all mapped`.
   - d. Reading the tasks top to bottom, no task depends on a later one.
   - e. All six § Security lines answered.
7. **Report** the path, the task count, and the mapping count from 6c. Do not commit, stage, or
   implement.

## Lifecycle

`prd/README.md` owns the three stages. `/prd` writes into `prd/_to_refine/` and moves nothing.
`progress.md` belongs to `/implement-prd` — do not create it here.

## KISS gate

Default: **no** new table, **no** new column, **no** new model, **no** new controller, **no** new
service class, **no** new gem, **no** new Stimulus controller. Each one the PRD proposes carries a
one-line `why` where it is listed.

A `why` must name the specific existing thing you considered instead — the column, the service, the
Stimulus controller, the gem already in `Gemfile.lock` — and the concrete reason it does not fit. A
`why` that only restates the feature ("needed to store the tolerance") fails the gate: cut the thing,
or reuse the alternative. See `docs/agent-rules.md` § Style.

---

## project.md template

````markdown
# <Feature Name>

## Overview

Two or three sentences: what this is, who it is for (teacher, student, or both), and the outcome for
them. Outcome, not implementation.

## Requirements

### Functional

- FR-1 (teacher | student | both) — <testable statement>
- FR-2 (teacher | student | both) — <testable statement>

Numbering is mandatory: the Implementation Tasks cite these ids. "Fast" is not testable; "no N+1 on the
results page" is. Teacher side and student side are different threat models — the tag is not decoration.

## Technical Approach

Default is nothing new. Anything new below carries a `why` on the same line (§ KISS gate).

### Affected Areas

Real paths only. This list is also the scope rail: `/implement-prd` stops if a diff touches a path that
is neither listed here nor the task's proof file.

- Models: `app/models/...`
- Controllers: `app/controllers/...`
- Views: `app/views/...`
- Services: reuse first — see `docs/agent-rules.md` § Style and `app/services/`. A new service needs a `why`.
- Jobs: `app/jobs/...` (Solid Queue).
- Tests: `test/...`

### Database Changes

| Table | Change | Why |
|---|---|---|

`N/A — no schema change` is the expected answer for most features. Prefer an existing column or a
JSON `config` key over a migration. If there is a migration, name the file and say whether it is
backfill-safe.

### Routes

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|

Helper names follow the `/tests` ↔ `Exam` split — `test_path`, not `exam_path`. Verify every helper
against `config/routes.rb`. Naming rules: `docs/agent-rules.md` § Domain and naming. Auth column: authenticated teacher, or
unauthenticated `Take::`.

This app is server-rendered. A new route is normally a **controller action + ERB view + Turbo
Stream target** — not a JSON endpoint. If the PRD proposes JSON, justify it here.

### Views & Hotwire

- **Views/partials**: `app/views/...` added or changed. Name the page region that changes and whether
  it is a Turbo Frame.
- **Stimulus**: `app/javascript/controllers/...`. Reuse before adding (`autosave`, `autosubmit`,
  `countdown`, `clipboard`, `ordering`, `live_board`, `dismiss`).
- **Turbo targets**: Frame and Stream ids, e.g. `live_board`,
  `dom_id(question, :student_answer)`.
- **Broadcasts**: does `LiveBoard` or `GradeLive` fire? Name the stream, target, and partial.
  If none, say none.
- **New gem**: only with a `why` (§ KISS gate).

## Security

Mandatory. Answer every line in writing. `N/A — <why>` is a valid answer; a missing line is not.
The rules are in `docs/agent-rules.md` § Security — state compliance, do not restate them.

- **Student-facing output** — does this render or serialize question data to a student? If yes: name each
  field sent, as an allowlist, and the `Question` student-facing reader that strips the key. The readers,
  and why hardening `QuestionSanitizer` alone changes nothing a student sees:
  `docs/agent-rules.md` § Never leak answer keys.
- **Teacher data** — does this read or write teacher-owned records? If yes: name the exact scope —
  `Current.user.<assoc>.find`, or the ownership join.
- **Unauthenticated `Take::`** — does this add or change a `Take::` action? If yes: name the
  `Assignment.find_by!(access_token: params[:token])` lookup and every record reached from it, and
  confirm no `Current.user` is introduced. A student-facing action *outside* `Take::` is a stop — ask.
- **Assignment tokens** — does this touch `/t/:token`, `Assignment#access_token`, or anywhere a
  token could reach a log, an export, or a fixture?
- **Params** — does this accept new params? List each one and the `permit` list it lands in.
- **Broadcasts and jobs** — does a Turbo broadcast or a Solid Queue job carry this data to an
  audience other than the request that triggered it? Teacher streams must not reach students.

Every "yes" above becomes a test — see § Testing Strategy.

## Localization

Localization rules: `docs/agent-rules.md` § Style. List every new key and its Ukrainian text.

| Key | Ukrainian text |
|---|---|

No bare literals in ERB, controllers, or flash messages.

## UI/UX — User Flow

1. <step> → <step> → <step>

Name the page region that changes at each step, and which region is a Turbo Frame.

## Edge Cases

- Empty state, single record, large class.
- Attempt already submitted / expired / auto-expired by `ExpireAttemptJob` or swept by
  `ExpireOverdueAttemptsJob`.
- Exam draft vs published vs closed.
- Token revoked or regenerated mid-flow.
- Teacher-scored question types with no grade yet.

## Out of Scope

Explicit list. This is what stops scope creep during `/implement-prd`, and it is handed to a reviewer
verbatim. Always present.

## Open Questions

- <question> — blocking / non-blocking

Blocking questions must be resolved before this leaves `_to_refine/`.

## Testing Strategy

Name real files. One line each: what it proves.

- `test/integration/` — request-level behavior. One file per feature area
  (`test/integration/assignments_manage_test.rb` is the pattern to copy).
- `test/integration/mvp_flow_test.rb` — **extend this** when the end-to-end
  teacher → assign → student takes → grade flow changes. Do not fork a parallel flow test.
- `test/integration/n_plus_one_test.rb` — extend when a new page loads a collection.
- `test/services/` — scoring, lifecycle, broadcast logic.
- `test/models/` — validations, scopes, state transitions.
- Security tests are not optional: each "yes" in § Security needs a test that fails when the
  guard is removed.

Quality loop and commands: `docs/agent-rules.md` § Quality.

## Implementation Tasks

One commit per task. This section is the contract handed to `/implement-prd`. Everything above is
context; this is what gets executed.

One flat ordered list. **The order is dependency order, not priority order.** Every task is mandatory —
`/implement-prd` does not finish with an unticked box. Genuinely optional work goes in § Out of Scope or
a follow-up PRD, never in this list.

Every task line has exactly this shape:

    - [ ] FR-<n> — <task> — done when: <assertion a test can make> — proof: `test/...`

- **`FR-<n>`** — the requirement this task builds. Every task cites one; every FR is cited by one.
- **`done when:`** — an observable acceptance criterion. A bare file path is not a criterion.
  "Works" is not a criterion. This text is handed to the reviewers verbatim.
- **`proof:`** — the test file that makes that assertion.
- **Sized to one reviewable commit.** Roughly one change plus its test. If a task needs a
  migration *and* a controller *and* a view, it is three tasks.
- **Ordered so the suite is green after every task.** Nothing may depend on a later task to
  compile or pass. Migration before the model that uses it; locale keys before the view that
  reads them; service before the controller that calls it.

<!-- example row, delete when writing a real PRD -->
- [ ] FR-1 — <task> — done when: <assertion> — proof: `test/...`
````

---

## Examples

### `/prd export class results to CSV`

Description supplied and unambiguous — no clarifying questions. Research first: `ExamsController#results`,
`app/views/exams/results.html.erb`, `Grade`, `Attempt`, `LiveBoard#snapshot` (already aggregates
per-assignment state), `config/locales/uk.yml`.

Creates `prd/_to_refine/export-class-results/project.md`. Excerpts:

**Routes**

| Verb | Path | Helper | Controller#action | Auth |
|---|---|---|---|---|
| GET | `/tests/:id/results.csv` | `results_test_path(format: :csv)` | `exams#results` | teacher |

Format added to the existing action via `respond_to`. No new route entry, no new controller.

**Database Changes** — N/A — reads `grades`, `attempts`, `assignments` as they stand.

**Security**

- Student-facing output — N/A — teacher-only action, no student surface.
- Teacher data — yes. Reuses `Current.user.exams.find(params[:id])`; rows come from
  `exam.assignments`, so no bare-id load is introduced.
- Unauthenticated `Take::` — N/A — no `Take::` action added or changed.
- Assignment tokens — yes, by omission: the CSV carries student name, score, submitted_at. It must
  **not** carry `access_token`. Proven by a test asserting the header and body.
- Params — yes: `format`. Constrained to `:csv` by `respond_to`; no new `permit` list.
- Broadcasts and jobs — N/A — synchronous download, nothing enqueued or broadcast.

**Implementation Tasks — one commit per task**

- [ ] FR-1 — Add `Exam#results_rows` — done when: rows are ordered by student name and contain exactly
      `[name, score, submitted_at]` — proof: `test/models/exam_test.rb`
- [ ] FR-1 — Add `respond_to :csv` to `ExamsController#results`, teacher-scoped — done when: a GET for
      `.csv` by the owning teacher returns the rows and a request by another teacher 404s —
      proof: `test/integration/exam_results_export_test.rb`
- [ ] FR-2 — Assert the CSV never carries `access_token` — done when: the test fails if `access_token`
      is added to the header or any row — proof: `test/integration/exam_results_export_test.rb`
- [ ] FR-3 — Add the `uk.yml` keys and the download button on `results.html.erb` — done when: the
      results page renders a link to the `.csv` format — proof:
      `test/integration/exam_results_export_test.rb`

### `/prd`

No description. Ask first — three questions, not ten:

1. Which question type, and is it auto-scored or teacher-scored?
2. Does it need a new student-facing input control, or does an existing one fit?
3. Does it change grading of existing exams, or only new ones?

Answers: a `numeric` type, auto-scored with a tolerance, new input, new exams only.

Then research `Question`, `Scoring`, `QuestionSanitizer`, `app/views/exams/show.html.erb` (the teacher
question editor lives there, not in `app/views/questions/`), `app/views/take/runs/`, and
`test/services/scoring_test.rb` before creating `prd/_to_refine/numeric-question-type/project.md`.

Two things that PRD must get right:

**Open Questions (blocking)** — adding to the `question_type` set touches `docs/agent-rules.md` § Domain and naming,
which enumerates the six existing types. The contract file has to be updated by the user, not
silently diverged from. Resolve before this leaves `_to_refine/`.

**Implementation Tasks.** Note the ordering: tolerance is stored in the existing `config` JSON, so
there is no migration, and each task leaves the suite green.

- [ ] FR-1 — Accept `numeric` in `Question` validation with `config["tolerance"]` — done when: a
      `numeric` question with a tolerance validates and one without it does not —
      proof: `test/models/question_test.rb`
- [ ] FR-2 — Score `numeric` in `Scoring` with tolerance, all-or-nothing — done when: a response inside
      the tolerance scores full and one outside scores zero — proof: `test/services/scoring_test.rb`
- [ ] FR-3 — Render prompt only for `numeric` in `app/views/take/runs/show.html.erb`, and mirror it in
      `QuestionSanitizer` — done when: the student page and the sanitizer payload both carry the prompt
      and neither carries the expected value or tolerance — proof: `test/models/question_test.rb`
- [ ] FR-4 — Teacher editor input in `app/views/exams/show.html.erb`, plus `uk.yml` keys — done when:
      selecting `numeric` renders the tolerance input and `POST test_questions_path` persists it —
      proof: `test/integration/exam_tabs_test.rb`, extended
- [ ] FR-5 — Student input in `app/views/take/runs/`, wired to the existing `autosave` controller —
      done when: a student can enter a numeric answer and it autosaves —
      proof: `test/integration/mvp_flow_test.rb`, extended
