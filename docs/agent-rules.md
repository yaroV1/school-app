# Agent rules — school-app

Teacher-owned tests app. Teachers sign in, build tests under a subject, and assign them. Students have no
accounts: they open a unique `/t/:token` link, take the test, and never authenticate. Rails 8.1, Hotwire
(Turbo + Stimulus), importmap, Propshaft, Tailwind, Minitest, SQLite — four databases in production, Solid
Queue / Cache / Cable, no Redis, no Postgres. Ukrainian UI. The schema allows multiple `User` teacher
records; always scope by owner.

## This contract

Everything an agent must follow is in this file. Read it before your first edit in a session.

Tool entry points add mechanics only, and point here:

- `CLAUDE.md` — Claude Code: skill routing, permissions, and the best-effort git guard.
- `AGENTS.md` — the generic/Codex entry point.
- `.cursor/rules/conventions.mdc` — Cursor frontmatter.

The PRD workflow is **Claude Code-native**: `/prd` and `/implement-prd` live in
`.claude/skills/prd/SKILL.md` and `.claude/skills/implement-prd/SKILL.md`; `prd/README.md` owns the stage
lifecycle. Cursor may discover those skills through its Claude compatibility path. In either tool they run
only when the developer invokes them — see § When to ask vs inspect. This repo does not expose them as
Codex skills; do not improvise the flow by hand.

**A new rule goes in this file.** If it must live anywhere else, this file names it here.

## Domain and naming

Do not invent tables, columns, routes, or APIs. Check `db/schema.rb`, `config/routes.rb`, and existing
code before assuming anything.

- Model/table: `Exam` / `exams`. An exam belongs to a `Subject`; a subject belongs to a `ClassGroup`.
- URLs say `/tests` everywhere (`path: "tests"` on both exam route blocks), but only the top-level block
  adds `as: :tests` → `test_path`, `edit_test_path`, `publish_/close_/results_/live_test_path`,
  `manage_test_assignments_path`. The nested new/create pair under a subject keeps the model name:
  `new_subject_exam_path`, `subject_exams_path`. There is no `tests_path` and no `subject_test*` helper.
- Create and list tests from the subject page. Students stay on the class, shared across subjects.
- Students belong to a teacher and join classes via `class_memberships`. Add students and subjects from the
  class page; students are creatable only nested under a class. No top-level Students/Tests nav.
- Student-facing controllers are `Take::`, never `Student::` (`app/controllers/take/`) — the module name
  avoids clashing with the `Student` model. URLs stay `/t/:token`. The route scope is `as: :student`, so the
  helpers go the other way: `student_portal_path`, `student_start_path`, `student_run_path`,
  `student_answers_path`, `student_submit_path`, `student_done_path`. There is no `take_*` helper.
- Question types: `mcq`, `short_text`, `open`, `ordering`, `matching`, `source`.
- Auto-scored: mcq, ordering (all-or-nothing), matching (partial credit, `points × correct / pairs`).
  Teacher-scored: short_text, open, source.

## Style

- Follow Rails layout and copy nearby code. Prefer simple, explicit changes.
- Extract a service for nontrivial domain or security logic. Existing: `Scoring`, `AttemptLifecycle`,
  `TokenGenerator`, `LiveBoard`, `GradeLive` — plus `LiveBroadcast`, which is **not** a service but a
  mixin. Read `app/services/` and reuse before adding another. Do not add layers "for SOLID."
- **Turbo naming.** Stream name is `[record, :channel]` — `turbo_stream_from @exam, :live_board` must pair
  with `broadcast_replace_to(@exam, :live_board, …)`. Broadcast the same partial the page renders, with the
  same locals — rendered inline (`attempts/show.html.erb` renders `attempts/live_header`) or through a lazy
  frame's `src` (`exams/live.html.erb` frames `live_board`, which `ExamsController#live` renders on the frame
  request). The target is whatever id the partial's own root element declares — never an id you derive from
  the partial's name: `dom_id(record, :prefix)` for a per-record block
  (`attempts/_student_answer.html.erb`), a fixed literal id for a page singleton (`live_board` in
  `exams/_live_board.html.erb`, `attempt_live_header` in `attempts/_live_header.html.erb`). Open the partial
  and read line 1. A mismatched name fails silently — no error, no failing test, the page just stops
  updating. Assert the target in a test.
- **Comments.** This codebase comments the non-obvious decision, not the code. A comment says why this shape
  was chosen or what breaks without it (see `live_broadcast.rb`, `attempt_lifecycle.rb`'s `rescue Expired`,
  `apply_answers!`, `live_board_controller.js`). Models carry none. Do not narrate what the line does.
- New UI strings go in `config/locales/uk.yml`. Default locale is `uk`. Raise user-facing errors through
  `I18n.t`, including from service objects.
- Check `Gemfile.lock` (and the gem version in use) before assuming third-party APIs.

## Security

Teacher data: scope through `Current.user` associations (`Current.user.exams.find`) **or** an equivalent
ownership join (`Attempt.joins(assignment: :exam).where(exams: { teacher_id: Current.user.id })`). Never load
a teacher resource by bare id. The schema is multi-teacher — "there is only one teacher" is not a scope.

Exception: `Take::` controllers are unauthenticated. They resolve
`Assignment.find_by!(access_token: params[:token])`, then scope attempts and answers through that
assignment. Do not add `Current.user` there. Proposing it in review is a wrong finding, not a fix.

### Never leak answer keys unintentionally

The live student path is `app/views/take/runs/show.html.erb`, which calls the `Question` student-facing
readers directly: `student_facing_options`, `display_items_for`, `shuffled_right_items`,
`student_facing_left`, `source_text`. There is no sanitizer layer between it and the response, so a leak
introduced there ships. The only other student answer-key surface is the finalized result at
`app/views/take/submissions/_correct_answer.html.erb`: it intentionally reveals the answer for auto-scored
types only when the exam setting allows it and the teacher finalized the grade.

`test/integration/answer_key_leak_test.rb` renders both surfaces as an unauthenticated student. It asserts
that no key reaches the live page and that the finalized result carries only the intentionally published
auto-scored answers. Extend it whenever you add a question type or a student-facing field; a new type with
no entry there is untested by construction.

Build every student payload as an **allowlist** — name each key you send. Never pass `question.config` or a
sub-hash of it through; the readers do this with `slice("id", "text")`.

- MCQ: option `id` + `text`. Never `is_correct`; the finalized result identifies the correct option by text
  without serializing that flag.
- Ordering: items shuffled with the **attempt** as seed — `question.display_items_for(answer, @attempt.id)`.
  `Question#stable_seed` keeps the order stable per (question, seed) so a reload does not reshuffle under the
  student. Always pass `@attempt.id` explicitly; the student-facing readers have no default seed, and using
  `question.id` instead would give every student in the class the same order and defeat the point.
- Matching: left items and shuffled right items. Never serialize `config["pairs"]`. A student **response**
  may use `payload["pairs"]` / `payload["order"]` — that is not the key. The finalized result may resolve
  the stored mapping into allowlisted left/right text, but must not send the mapping or its ids.
- Source: `source_text` and the prompt, nothing else from `config` — `rubric` and `model_answer` live in the
  same hash.
- short_text / open: prompt only. No config is student-visible.
- Never send rubric or model answer, for any type. The finalized result reveals correct answers only for
  `mcq`, `ordering`, and `matching`; teacher-scored types reveal score and comments only.

### Params

Strong params for every teacher-facing model write. Two deliberate exceptions, both on paths where a permit
list would break behavior:

- The student answer payload is nested per question type, so `Take::AnswersController#normalize_answers` and
  `Take::SubmissionsController#submitted_answers` hand `to_unsafe_h` to `AttemptLifecycle`, which re-shapes
  it per type into the schemaless `answers.payload` JSON column.
- `AttemptsController#update` assigns `teacher_score` / `teacher_comment` attribute-by-attribute.

Do not "fix" either into a `permit` list — it drops the per-type nested keys and silently breaks autosave and
submit. Never `permit!`. Never widen `to_unsafe_h` to another model or controller.

### Tokens

Assignment tokens are secrets. Do not add them to application logs and do not commit them.
`config/initializers/filter_parameter_logging.rb` includes `:token`, so params are redacted; request paths
like `/t/:token` still appear in HTTP logs — treat those logs as sensitive. Do not weaken CSRF, session
cookies, or `has_secure_password`.

## Attempt lifecycle

The concurrency rules in `app/services/attempt_lifecycle.rb`. A student mid-exam is the one user who cannot
retry, so these are invariants, not preferences.

- **Lock and re-check.** Any change to an attempt's status or answers re-reads the row under
  `Attempt.lock.find(attempt.id)` and re-checks `in_progress?` / `past_deadline?` on that locked copy before
  writing. Guards checked before the lock are advisory. `save_answers!` and `submit!` wrap this in
  `Attempt.transaction`; `expire!` does not, because a sweep also calls it. The locked row never escapes —
  return and broadcast the caller's own `attempt`, reloaded.
- **What actually serializes writers.** `.lock` emits nothing on SQLite — Arel drops the clause, so
  `Attempt.lock.find` is a plain `SELECT`. The transaction is the real guard: `default_transaction_mode` is
  `:immediate`, so `Attempt.transaction` takes the database write lock at `BEGIN` and holds it to `COMMIT`,
  and no one else can commit in the window between the read and the write. A write path inside a transaction
  therefore cannot lose the `lock_version` race; one that reads outside a transaction can, which is why
  `expire!` — the only such path — rescues `StaleObjectError`. Never drop an `Attempt.transaction` wrapper on
  the theory that `.lock` is holding the row, and keep `lock_version` on `attempts`: it is what catches the
  unwrapped read, and what carries the invariant to an adapter where `.lock` does emit `FOR UPDATE`.
- **Conflicts.** `save_answers!` rescues `ActiveRecord::StaleObjectError`, retries the transaction **once**,
  then raises `AttemptLifecycle::Conflict`. Never retry more than once. `submit!` translates the same error
  into `Conflict` with **no** retry — `save_answers!` owns the retry policy. Both `Take::` write actions
  rescue `Conflict` and answer the student with `take.errors.save_conflict`; it is handled, not a 500.
  `expire!` rescues the same error but answers it differently: its read is **not** in a transaction, so a
  collision means another writer already moved the row and won — it reloads and returns `nil` ("not this
  call") instead of raising. It runs inside a student's save and submit, ahead of their `Conflict` rescue,
  where raising is a 409 mid-exam; a row still overdue waits for the next `ExpireOverdueAttemptsJob` sweep.
  A conflicted `submit!` that carried answers **still broadcasts them** — `save_answers!` committed them in
  its own transaction and skipped the push on the promise that `submit!` would make it, and the rollback
  cancels the submission, not the student's work. Answers only: no status changed, so the board stays put.
  All three are pinned in `test/integration/save_conflict_test.rb` and `test/services/attempt_lifecycle_test.rb`.
- **Rollback and expiry.** If a transaction rolls back because the attempt expired, re-run
  `expire_if_needed!` on a reloaded attempt **outside** the transaction before re-raising. State that dies
  with the rollback must be written again, or the attempt stays `in_progress` past its deadline.
- **Broadcast after commit, never inside.** Push only what changed: the runner posts the whole form every
  few seconds, so a write path returns the subset that moved and skips the broadcast when that subset is
  empty. A sweep refreshes each affected board **once** at the end, not once per record.
- **Stream routing.** Attempt status or the assignment set → `LiveBoard.replace(exam)`. Answer content →
  `GradeLive.replace_answers`. A transition changing header *and* answers (submit, expire) →
  `GradeLive.replace_header_and_answers` **plus** the board. Autosave must not touch the board.
- **Broadcast only from a service, inside `broadcast_safely`.** A cable outage or a template error must
  never turn a student's request into a 500. Any code that broadcasts must `include LiveBroadcast`.

## Quality

After changing behavior, in this order:

1. Add or update Minitest coverage in the file that already owns the behavior (see § Where things are).
2. `bin/rubocop -A <files you touched>` **first** — it rewrites source, unsafe cops included, so running it
   after the tests invalidates them. Only files you touched: repo-wide lint is deferred to `bin/ci`, which
   runs `bin/rubocop` unscoped.
3. `bin/rails test`
4. `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` when the diff touches `app/`.
5. `bin/bundler-audit` when the diff touches `Gemfile` or `Gemfile.lock`.
6. `bin/importmap audit` only when JS dependencies change. There is no JS style linter.

No coverage %. Never report a check as passing without running it.

`bin/ci` runs the whole thing locally (`config/ci.rb`), but it is **not** read-only: its first step is
`bin/setup --skip-server`, which touches the dev database. On top of `.github/workflows/ci.yml` it adds
that Setup step and a seed replant; every check the two share runs with the same flags. It also greps
`app/` for Cyrillic, which is how "no user-visible literals in code" is enforced.

There are no system tests, so browser behavior has no automated coverage: autosave, the server countdown,
drag-to-reorder, the live board's broadcast-plus-poll reconciliation. Cover what you can with an
integration test that asserts rendered markup (`test/integration/answer_key_leak_test.rb` is the pattern).
`capybara` and `selenium-webdriver` stay in the `:test` group; add the CI job back in the same commit as
the first system test, not before.

## Git

- Never `git commit` or `git push` unless the user explicitly asks in that message.
- Exception, and the only one: invoking `/implement-prd` **is** that explicit request, for that run, on the
  current branch — `git add` of files the run touched, `git commit` (one per task plus the completion
  commit), and the `prd/backlog → prd/complete` `git mv`. Nothing else: no push, no `--amend`, no new
  branch, no PR. Scope and limits: `.claude/skills/implement-prd/SKILL.md` § Git authorization.
- Never `--no-verify`, never force-push, never change git config.
- Never `git add -A`, `git add --all`, or `git add .` — stage the files you touched, by name.
- Never run a command that throws away uncommitted work: `git stash`, `git clean`, `git reset --hard`,
  `git restore`, `git checkout --`. The tree is the user's, not scratch space.
- Remote is personal GitHub (`https://github.com/yaroV1/school-app`). Never push through a work GitHub
  account, and do not add a second remote.
- In Claude Code, permissions and a best-effort hook block common forbidden forms (see `CLAUDE.md`); they
  are not a complete shell parser. A blocked command means you hit a rule in this section, not a tooling
  bug. Cursor and Codex have no project git guard — the rules bind you either way, and nothing there catches
  the mistake before it lands.

## Where things are

- Models: `app/models/` · schema: `db/schema.rb`
- Services: `app/services/` — read the directory before adding one
- Teacher controllers: `app/controllers/` · auth: `app/controllers/concerns/authentication.rb`
- Student controllers: `app/controllers/take/` · views: `app/views/take/`
- Question editor: `app/views/exams/show.html.erb` (`app/views/questions/` holds partials only)
- Stimulus: `app/javascript/controllers/` · pins: `config/importmap.rb`
- Strings: `config/locales/uk.yml` · Routes: `config/routes.rb` · Jobs: `app/jobs/`
- Tests — read `test/` before adding a file:
  - `test/services/` — scoring, attempt lifecycle, availability windows and expiry.
  - `test/integration/` — request-level flows: `mvp_flow_test.rb` (the teacher→student spine),
    `n_plus_one_test.rb` (query counts), `grade_integrity_test.rb`, `live_board_test.rb`, tab/filter tests.
  - `test/models/`, `test/controllers/`
- PRDs: `prd/` — `prd/README.md` owns the stage lifecycle

## Review tests

Four checks on the finished diff, run after `bin/rails test` is green and before reporting the change done.
Answer each in one line naming the evidence; if you cannot write the line, the diff is not done. On the
`/implement-prd` path the implementing agent answers the first three itself at § The loop step 4, and the
review fan-out owns Security.

- **KISS.** A new class, module, or service needs a second caller, a security boundary, or nontrivial
  domain logic. None of the three: inline it. A new option or flag needs the caller that passes it.
- **The Rails way.** Name the file in this repo the change resembles. A pattern with no precedent here needs
  a stated reason, and new behavior maps onto the nouns in § Domain and naming and `db/schema.rb`.
- **Clean code.** Each new method described in one sentence with no "and", named from the domain
  vocabulary. If the diff adds code to an existing file and deletes none, name the path it replaces —
  additive-only change is how a codebase grows a second way to do one thing.
- **Security.** Name the evidence for each § Security rule the diff touches — the reader that strips the
  key, the ownership scope, the `permit` list. For a new export, log line, fixture, or broadcast: can an
  `access_token` reach it, and which assertion proves it cannot? "The UI never links to it" is not an
  answer — `/t/:token` is public.

## When to ask vs inspect

- If the codebase already has the answer, inspect it and proceed.
- Ask if the request is ambiguous. Prefer one clarifying question over building the wrong feature.
- If the choice is hard to reverse — a schema change, auth, scoring rules, a new question type — or the work
  needs more than one commit to keep the suite green: say so in one line and ask before building. Name a PRD
  as an option if one would help. Do not start one. Adding a route or a controller action is not on its own
  a reason to stop — most features add one.
- None of those: just do it.

`/prd` and `/implement-prd` run **only when the developer invokes them**, by slash command or by asking in
their own words. No rule here starts either, and neither does the size or risk of a change.
