# Agent rules — school-app

Teacher-owned tests app. Teachers sign in, build tests under a subject, and assign them. Students have no
accounts: they open a unique `/t/:token` link, take the test, and never authenticate. Rails 8.1, Hotwire
(Turbo + Stimulus), importmap, Propshaft, Tailwind, Minitest, SQLite — four databases in production, Solid
Queue / Cache / Cable, no Redis, no Postgres. Ukrainian UI. The schema allows multiple `User` teacher
records; always scope by owner.

## This contract

Everything an agent must follow is in this file. Read it before your first edit in a session.

Tool entry points add mechanics only, and point here:

- `CLAUDE.md` — Claude Code: skill routing, and mechanical enforcement of § Git.
- `AGENTS.md` — the generic/Codex entry point.
- `.cursor/rules/conventions.mdc` — Cursor frontmatter.

Workflow contracts, invoked rather than read: `.claude/skills/prd/SKILL.md`,
`.claude/skills/implement-prd/SKILL.md`, `prd/README.md` (PRD stage lifecycle — sole owner).

Historical, not current: `docs/TECHNICAL_PLAN.md`. It predates subjects, the `Take::` namespace, three of
the six question types, and it names Postgres. Do not cite it as current. Do not edit it unless asked.

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
  `QuestionSanitizer`, `TokenGenerator`, `LiveBoard`, `GradeLive` — plus `LiveBroadcast`, which is **not** a
  service but a mixin. Read `app/services/` and reuse before adding another. Do not add layers "for SOLID."
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

### Never leak answer keys

The live student path is `app/views/take/runs/show.html.erb`, which calls the `Question` student-facing
readers directly: `student_facing_options`, `display_items_for`, `shuffled_right_items`,
`student_facing_left`, `source_text`. **That is the only boundary.** `QuestionSanitizer` states the same
policy as a payload object and is covered by `test/models/question_test.rb`, but no application code calls
it — hardening it alone changes nothing a student sees. If you change one, change both.

Build every student payload as an **allowlist** — name each key you send. Never pass `question.config` or a
sub-hash of it through; the readers do this with `slice("id", "text")`.

- MCQ: option `id` + `text`. Never `is_correct`.
- Ordering: items shuffled with the **attempt** as seed — `question.display_items_for(answer, @attempt.id)`.
  `Question#stable_seed` keeps the order stable per (question, seed) so a reload does not reshuffle under the
  student. Never rely on the sanitizer's default seed: it falls back to `question.id`, which gives every
  student in the class the same order and defeats the point.
- Matching: left items and shuffled right items. Never `config["pairs"]`. A student **response** may use
  `payload["pairs"]` / `payload["order"]` — that is not the key.
- Source: `source_text` and the prompt, nothing else from `config` — `rubric` and `model_answer` live in the
  same hash.
- short_text / open: prompt only. No config is student-visible.
- Never send rubric or model answer, for any type.

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
- **Conflicts.** `save_answers!` rescues `ActiveRecord::StaleObjectError`, retries the transaction **once**,
  then raises `AttemptLifecycle::Conflict`. Never retry more than once. Know the current gap before you rely
  on this: `submit!` and `expire!` take the same lock with no such rescue, and no controller rescues
  `Conflict`, so a lost optimistic-lock race still reaches a student as a 500. Closing that is a behavior
  change needing its own tests — do not review a diff as though the guarantee already holds.
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
`bin/setup --skip-server`, which touches the dev database. It is also not identical to
`.github/workflows/ci.yml` — it adds a Setup step and a seed replant, and it runs Brakeman *stricter* than
CI (`--exit-on-warn --exit-on-error` locally vs a bare `bin/brakeman --no-pager` on GitHub), so a red
Brakeman step locally is not proof the PR will be red.

`.github/workflows/ci.yml` defines a `system-test` job, but `test/system/` does not exist — the repo has
zero system tests and capybara/selenium are unused scaffolding. That job exercises nothing. Browser-level
behavior has no automated coverage anywhere; cover it with an integration test.

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
- In Claude Code these absolutes are also enforced mechanically (see `CLAUDE.md`). A blocked command means
  you hit a rule in this section, not a tooling bug. Other tools have no such backstop — the rules bind you
  either way.
- `.gitignore` negates `/AGENTS.md` because some global gitignores exclude it. If it ever goes untracked,
  `git add -f AGENTS.md`.

## Where things are

- Models: `app/models/` · schema: `db/schema.rb`
- Services: `app/services/` — read the directory before adding one
- Teacher controllers: `app/controllers/` · auth: `app/controllers/concerns/authentication.rb`
- Student controllers: `app/controllers/take/` · views: `app/views/take/`
- Question editor: `app/views/exams/show.html.erb` (`app/views/questions/` holds partials only)
- Stimulus: `app/javascript/controllers/` · pins: `config/importmap.rb`
- Strings: `config/locales/uk.yml` · Routes: `config/routes.rb` · Jobs: `app/jobs/`
- Tests — read `test/` before adding a file:
  - `test/services/` — scoring and attempt lifecycle. Availability windows and the expiry job are in
    `phase11_test.rb`, which the name does not advertise.
  - `test/integration/` — request-level flows: `mvp_flow_test.rb` (the teacher→student spine),
    `n_plus_one_test.rb` (query counts), `grade_integrity_test.rb`, `live_board_test.rb`, tab/filter tests.
  - `test/models/`, `test/controllers/`
- PRDs: `prd/` — `prd/README.md` owns the stage lifecycle

## Review tests

The sections above state the rules; these are the tests for whether a diff honors them. Run them after
`bin/rails test` is green and before reporting the change done. Write one line per test naming the evidence
— the second caller, the precedent file, the deleted code, the reader that strips the key, the ownership
scope. If you cannot write the line, the diff is not done.

On the `/implement-prd` path the review fan-out applies these instead; the implementing agent does not
repeat them.

**KISS.** If the diff adds a class, module, or service, name the second caller, the security boundary, or
the nontrivial domain logic that justifies it. If you can name none of the three, inline it. If it adds an
option or a flag, name the caller that passes the non-default value.

**The Rails way.** Point at an existing file in this repo that the change resembles. A pattern with no
precedent here needs a stated reason. New behavior maps onto the nouns in § Domain and naming and
`db/schema.rb`, or it is probably the wrong shape.

**Clean code.** Describe each new method in one sentence with no "and". Names come from the domain
vocabulary in § Domain and naming; a reader who knows the domain should not need the body to guess what a
name means. No user-visible string literals in `.rb` or `.erb` — grep the diff for Cyrillic. If the diff adds code to an existing file and deletes none, name the code the new path replaces,
or state in one line why the old path still has callers. Additive-only change is how a codebase grows a
second way to do one thing.

**Security.** Re-read § Security against the diff and name the evidence for each rule it touches — the
reader that strips the key, the ownership scope, the `permit` list. If it adds an export, a log line, a
fixture, or a broadcast, state whether an
`access_token` can reach it and name the assertion that proves it cannot. "The UI never links to it" is not
an answer — `/t/:token` is public.

## When to ask vs inspect

- If the codebase already has the answer, inspect it and proceed.
- Ask if the request is ambiguous. Prefer one clarifying question over building the wrong feature.
- If the choice is hard to reverse — schema, auth, scoring rules, new question type behavior — or it adds a
  route or a controller action, spans a teacher-facing and a student-facing path, or needs more than one
  commit to keep the suite green: do not ask-then-build. Run `/prd`. Asking resolves ambiguity; `/prd`
  handles scope and irreversibility. None of those: just do it.
