# Technical Implementation Plan — Tests Platform (MVP first)

Product contract: approved Tests Platform PRD (MVP → 1.1 → 1.2 → 2). This document locks stack, data model, routes/UI approach, and build order for **MVP**, with extension hooks for phases **1.1**, **1.2**, and **2**.

---

## 1. Goals and constraints

- Single teacher; student access via unguessable assignment tokens only (no student accounts).
- Teacher-managed roster + ClassGroups; per-student attempt history.
- Question types: `mcq` (single correct), `short_text`, `open`.
- Server is source of truth for time, attempts, and scores.
- Target scale: ≤40 concurrent in-progress attempts, ≤500 roster students.
- Ship MVP so one real class test can run end-to-end without spreadsheets.

---

## 2. Stack (locked)

| Layer | Choice | Why |
|---|---|---|
| App framework | **Ruby on Rails 8** | Full-stack MVC; fits CRUD teacher app + token student flow |
| Front-end | **Hotwire (Turbo + Stimulus)** | Server-rendered HTML, progressive enhancement, minimal JS |
| CSS | **Tailwind CSS** (via `tailwindcss-rails`) | Fast UI without a separate SPA |
| Auth (teacher) | **Rails 8 authentication generator** (session + `has_secure_password`) | One teacher account; no SSO |
| DB | **SQLite** | Simple local/personal deploy; no Docker required |
| ORM | **ActiveRecord** | Native Rails |
| Test entity | **`Exam` model / `exams` table** | Avoids clashing with Minitest `Test`; UI & routes remain `/tests` |
| Jobs | **Solid Queue** | DB-backed jobs (expiry, later AI grading) — part of Solid Trifecta |
| Cache | **Solid Cache** | DB-backed cache — Solid Trifecta |
| Pub/sub / Cable | **Solid Cable** (Action Cable adapter) | Solid Trifecta; used lightly in MVP, primary for phase 2 live board |
| Tests | **Minitest** (+ system tests with Capybara) | Rails default |
| Hosting (suggested) | **Single VPS / Kamal**, or any host that runs Puma + SQLite | Rails-native deploy |

**Solid Trifecta usage by phase**

| Component | MVP | 1.1 | 1.2 | 2 |
|---|---|---|---|---|
| Solid Queue | Configure; optional `ExpireAttemptJob` | Recurring/lazy expiry jobs | `AiDraftGradeJob` | Force-expire fan-out if needed |
| Solid Cache | Fragment/Russian-doll where useful | Cache live-status payloads briefly | Cache prompt templates | Presence snapshot cache (optional) |
| Solid Cable | Wired up; unused for product UX | Optional Turbo Stream pings | — | Teacher live board + student heartbeat channels |

**Repo layout (MVP)**

```text
school-app/
  docs/
    TECHNICAL_PLAN.md
  app/
    controllers/
      sessions_controller.rb
      students_controller.rb
      class_groups_controller.rb
      tests_controller.rb
      questions_controller.rb          # or nested under tests
      assignments_controller.rb
      attempts_controller.rb           # teacher grading
      student/
        portals_controller.rb         # /t/:token landing
        runs_controller.rb            # start / runner
        answers_controller.rb         # autosave
        submissions_controller.rb     # submit
    models/
      user.rb
      student.rb
      class_group.rb
      class_membership.rb
      test.rb
      question.rb
      assignment.rb
      attempt.rb
      answer.rb
      grade.rb
    services/
      token_generator.rb
      scoring.rb
      attempt_lifecycle.rb
      question_sanitizer.rb
    jobs/
      expire_attempt_job.rb           # thin in MVP; fuller in 1.1
    views/
      layouts/
        teacher.html.erb
        student.html.erb
      students/ class_groups/ tests/ assignments/ attempts/
      student/portals/ student/runs/
    javascript/
      controllers/                    # Stimulus
        clipboard_controller.js
        autosave_controller.js
        countdown_controller.js
        sortable_questions_controller.js
    channels/                         # Action Cable (phase 2 ready)
  config/
    routes.rb
    queue.yml                         # Solid Queue
    cable.yml                         # Solid Cable
    cache.yml                         # Solid Cache
  db/
    migrate/
    seeds.rb
  test/
```

---

## 3. Domain → database schema (MVP)

ActiveRecord / SQLite. Use `bigint` PKs (Rails default) unless UUID is preferred later — **MVP uses default integer IDs**. JSON columns use `json` (not `jsonb`).

### 3.1 Enums (Rails 7+ native enums)

```ruby
# Test
enum :status, { draft: 0, published: 1, closed: 2 }, validate: true

# Question
enum :question_type, { mcq: 0, short_text: 1, open: 2 }, validate: true

# Attempt
enum :status, { in_progress: 0, submitted: 1, expired: 2, abandoned: 3 }, validate: true
```

Note: PRD lists `not_started` on Attempt. Implement **not started** as “no Attempt row yet” (assignment exists, zero attempts).

### 3.2 Tables (conceptual migration)

```ruby
create_table :users do |t|
  t.string :email, null: false
  t.string :password_digest, null: false
  t.string :name
  t.timestamps
end
add_index :users, :email, unique: true

create_table :students do |t|
  t.references :teacher, null: false, foreign_key: { to_table: :users }
  t.string :name, null: false
  t.string :email
  t.datetime :archived_at
  t.timestamps
end

create_table :class_groups do |t|
  t.references :teacher, null: false, foreign_key: { to_table: :users }
  t.string :name, null: false
  t.timestamps
end

create_table :class_memberships do |t|
  t.references :class_group, null: false, foreign_key: true
  t.references :student, null: false, foreign_key: true
  t.timestamps
end
add_index :class_memberships, %i[class_group_id student_id], unique: true

create_table :tests do |t|
  t.references :teacher, null: false, foreign_key: { to_table: :users }
  t.string :title, null: false
  t.text :description
  t.integer :status, null: false, default: 0 # draft
  t.integer :time_limit_sec # null = untimed
  t.integer :max_attempts, null: false, default: 1
  # Phase 1.1: t.datetime :available_from, :available_until
  t.timestamps
end

create_table :questions do |t|
  t.references :test, null: false, foreign_key: true
  t.integer :question_type, null: false
  t.text :prompt, null: false
  t.integer :points, null: false, default: 1
  t.integer :position, null: false, default: 0
  # MCQ: { "options" => [{ "id" => "...", "text" => "...", "is_correct" => true/false }] }
  # SHORT_TEXT / OPEN: { "rubric" => "...", "model_answer" => "..." }
  t.jsonb :config, null: false, default: {}
  t.timestamps
end

create_table :assignments do |t|
  t.references :test, null: false, foreign_key: true
  t.references :student, null: false, foreign_key: true
  t.string :access_token, null: false
  t.datetime :revoked_at
  t.timestamps
end
add_index :assignments, :access_token, unique: true
add_index :assignments, %i[test_id student_id], unique: true

create_table :attempts do |t|
  t.references :assignment, null: false, foreign_key: true
  t.integer :status, null: false, default: 0 # in_progress
  t.integer :attempt_no, null: false
  t.datetime :started_at, null: false
  t.datetime :deadline_at
  t.datetime :submitted_at
  t.datetime :last_activity_at, null: false
  # Phase 1.1: t.integer :lock_version, default: 0, null: false
  t.timestamps
end
add_index :attempts, %i[assignment_id attempt_no], unique: true

create_table :answers do |t|
  t.references :attempt, null: false, foreign_key: true
  t.references :question, null: false, foreign_key: true
  # MCQ: { "option_id" => "..." } ; SHORT_TEXT/OPEN: { "text" => "..." }
  t.jsonb :payload, null: false, default: {}
  t.decimal :auto_score, precision: 8, scale: 2
  t.decimal :teacher_score, precision: 8, scale: 2
  t.text :teacher_comment
  # Phase 1.2 AI draft columns
  t.timestamps
end
add_index :answers, %i[attempt_id question_id], unique: true

create_table :grades do |t|
  t.references :attempt, null: false, foreign_key: true, index: { unique: true }
  t.decimal :total_score, precision: 8, scale: 2
  t.decimal :max_score, precision: 8, scale: 2, null: false
  t.text :teacher_comment
  t.boolean :finalized_by_teacher, null: false, default: false
  t.datetime :finalized_at
  t.timestamps
end
```

Also enable Solid Trifecta tables via Rails defaults / installers (`solid_queue`, `solid_cache`, `solid_cable` migrations).

### 3.3 Associations (sketch)

```ruby
# User (teacher)
has_many :students, foreign_key: :teacher_id
has_many :class_groups, foreign_key: :teacher_id
has_many :tests, foreign_key: :teacher_id

# Student
belongs_to :teacher, class_name: "User"
has_many :class_memberships
has_many :class_groups, through: :class_memberships
has_many :assignments

# Test → questions, assignments
# Assignment → attempts → answers, grade
```

### 3.4 Token generation

```ruby
# TokenGenerator
SecureRandom.urlsafe_base64(32) # ~256 bits
```

- Student URL: `/t/:access_token`
- Regenerate = new token; revoke = set `revoked_at`

---

## 4. Auth and authorization

### Teacher

- Session cookie via Rails 8 auth (`Session` model or equivalent generated code).
- `Authentication` concern: `require_authentication` before teacher controllers.
- All teacher queries scoped: `Current.user.students`, `Current.user.tests`, etc. (IDOR-safe).
- Layout: `layouts/teacher`.

### Student

- No user account.
- Credential = valid `access_token` on `Assignment`.
- Controllers under `Student::` resolve assignment by token; 404 if missing/revoked when appropriate.
- Layout: `layouts/student` (no teacher chrome).

### Authorization matrix

| Action | Actor | Rule |
|---|---|---|
| CRUD students/classes/tests | Teacher | Owns resource |
| Assign / revoke / regenerate | Teacher | Owns test + students |
| Start / save / submit attempt | Student | Valid non-revoked assignment; test `published`; under `max_attempts`; before deadline |
| Grade / finalize | Teacher | Owns attempt via test |
| View student history | Teacher | Owns student |

**Closed / revoked (PRD):** block **new starts**. In-progress attempts may continue until `deadline_at`, then expire.

---

## 5. Attempt lifecycle (MVP)

```text
[Assignment, 0 attempts]  --start-->  Attempt in_progress
       |                                    |
       |                              autosave answers
       |                                    |
       |                              submit (before deadline)
       |                                    v
       |                              submitted + Grade stub
       |
       +-- start again if attempt count < max_attempts
```

Implemented in `AttemptLifecycle` service (not fat controllers).

**Start**
1. Resolve assignment by token; reject if revoked or test not `published`.
2. Count attempts; reject if `count >= max_attempts`.
3. If existing `in_progress` attempt → resume (idempotent).
4. Else create with `attempt_no = count + 1`, `deadline_at = Time.current + time_limit_sec` (or nil).

**Autosave** (Stimulus + Turbo/`fetch` → `Student::AnswersController#upsert`)
- Upsert answers by `(attempt_id, question_id)`.
- Touch `last_activity_at`.
- If past deadline → expire, return error + redirect/stream “time ended”.

**Submit**
1. Ensure `in_progress` and `Time.current <= deadline_at`.
2. MCQ → `auto_score` via `Scoring`.
3. Status `submitted`; create/update `Grade` with `max_score`.
4. Teacher finalizes only when every question has a numeric score (`teacher_score` or `auto_score`).

**Expire (MVP)**
- Lazy on start/save/submit; optional `ExpireAttemptJob` via Solid Queue.
- Phase 1.1: stronger job + live board reads.

---

## 6. Scoring rules

| Type | Auto | Teacher |
|---|---|---|
| MCQ | `points` if selected `option_id` is correct, else `0` | Override allowed |
| SHORT_TEXT | none | `teacher_score` 0..points |
| OPEN | none | `teacher_score` 0..points |

Final `grade.total_score` = sum of (`teacher_score` || `auto_score`) once every question is scored and teacher finalizes.

---

## 7. Routes (MVP) — Hotwire-first, not JSON API-first

Teacher UX is standard Rails HTML + Turbo. Student autosave may return `turbo_stream` or `204`/`head :ok`.

```ruby
# config/routes.rb (sketch)
resource :session, only: %i[new create destroy]

resources :students do
  member { post :archive; post :unarchive }
end

resources :class_groups do
  member { put :members } # replace membership set
end

resources :tests do
  member do
    post :publish
    post :close
  end
  resources :questions, only: %i[create update destroy], shallow: true
  resources :assignments, only: %i[index create], shallow: false do
    collection { get :manage } # assign UI
  end
  get :results, on: :member
end

resources :assignments, only: [] do
  member do
    post :revoke
    post :regenerate_token
  end
end

resources :attempts, only: %i[show update] # teacher grade form

# Student token portal
scope "/t/:token", module: :student, as: :student do
  root to: "portals#show"                    # landing
  post "start", to: "runs#create"            # start / resume
  get  "run", to: "runs#show"                # runner
  put  "answers", to: "answers#upsert"       # autosave
  post "submit", to: "submissions#create"
  get  "done", to: "submissions#show"
end
```

**Status transitions**
- `draft → published` (≥1 question)
- `published → closed`
- Questions editable only in `draft`; title/description anytime.

---

## 8. UI (MVP)

### Teacher (authenticated)

| Path | Purpose |
|---|---|
| `/session/new` | Login |
| `/students` | Roster |
| `/students/:id` | History |
| `/class_groups` | Classes + members |
| `/tests` | List |
| `/tests/new`, `/tests/:id` | Create / edit + questions |
| `/tests/:id/assignments` (manage) | Assign, copy links, revoke/regenerate |
| `/tests/:id/results` | Results table |
| `/attempts/:id` | Grade |

Nav: Students · Classes · Tests. Turbo Drive for navigation; Stimulus for clipboard copy and question reorder.

### Student (public)

| Path | Purpose |
|---|---|
| `/t/:token` | Rules, start/resume |
| `/t/:token/run` | Runner + countdown + autosave |
| `/t/:token/done` | Confirmation only (no key reveal) |

Stimulus controllers:
- `countdown` — client display; server enforces deadline
- `autosave` — interval ~15s + `visibilitychange`/blur
- `clipboard` — copy assignment URL on teacher assign page

---

## 9. Key Ruby objects

| Object | Responsibility |
|---|---|
| `Current` | Current teacher user |
| `TokenGenerator` | Access tokens |
| `Scoring` | MCQ auto-score; finalize eligibility |
| `AttemptLifecycle` | start / resume / expire / submit |
| `QuestionSanitizer` | Strip `is_correct` / rubrics for student views |
| `ExpireAttemptJob` | Solid Queue expiry helper |

Pundit/ActionPolicy is optional; for single-teacher MVP, scoping via `Current.user` associations is enough.

---

## 10. MVP build order

1. **Scaffold** — `rails new` with Solid Queue/Cache/Cable; Postgres; Tailwind; auth; seed teacher.
2. **Roster** — Students + ClassGroups CRUD (Hotwire).
3. **Tests builder** — draft tests, nested questions, publish/close.
4. **Assignments** — tokens, manage page, revoke/regenerate, clipboard.
5. **Student runner** — portal, start/resume, autosave, submit, done.
6. **Results + grading** — results table, grade form, finalize; student history.
7. **Hardening** — IDOR, deadline, closed/revoked, empty states; Minitest coverage.
8. **Manual E2E** — PRD §5.3 checklist.

---

## 11. MVP acceptance criteria → verification

| # | PRD criterion | How we verify |
|---|---|---|
| 1 | ClassGroup ≥5 students, unique links | Assign page shows 5 distinct `/t/...` URLs |
| 2 | MCQ + short + open submit | System/manual runner |
| 3 | MCQ auto; open/short need teacher | `Scoring` tests + incomplete grade UI |
| 4 | Close/revoke block new starts | Request/integration tests on `runs#create` |
| 5 | Student history | `/students/:id` chronological |
| 6 | Server deadline | Submit after `deadline_at` fails; status `expired` |
| 7 | Max attempts | Start at limit fails |

Automated minimum: `Scoring` + `AttemptLifecycle` tests; a few system tests for happy path.

---

## 12. Phase extension hooks (do not build product UX yet)

### 1.1 — Session control hardened ✅

- `available_from` / `available_until` on `exams`.
- `lock_version` on `attempts` for optimistic autosave (last-write-wins on stale version).
- Live board: `/tests/:id/live` — Turbo Frame polling every 4s + new-submit toast; class filter.
- `ExpireOverdueAttemptsJob` on board load + recurring.yml every 30s.
- Bulk revoke on assign page; countdown uses server-time offset.

### 1.2 — AI draft grading

- Columns on `answers`: `ai_draft_score`, `ai_draft_comment`, `ai_model`, `ai_generated_at`.
- `grading_instructions` on `tests`.
- `AiDraftGradeJob` (Solid Queue); teacher-triggered; never overwrite finalized grades.
- UI: “AI suggestion — not final”; Accept / Edit / Ignore.

### 2 — Live progress

- Student heartbeat Stimulus → Action Cable (Solid Cable) or lightweight POSTs.
- Teacher subscribes to `TestStatusChannel` for presence + progress.
- Checklist of answered/unanswered; peek action for answer text; force-expire.
- Polling fallback if Cable disconnects.

MVP configures Solid Cable so phase 2 does not require a Redis dependency.

---

## 13. Environment / credentials (MVP)

```bash
# .env / credentials
DATABASE_URL=postgres://...
RAILS_MASTER_KEY=...
# Optional later:
# OPENAI_API_KEY=...   # phase 1.2
```

Solid Queue/Cache/Cable use SQLite (Rails 8 multi-db SQLite files is fine at this scale).

---

## 14. Local development

```bash
bin/setup                 # bundle, db:prepare, solid_* tables
bin/rails db:seed         # teacher@example.com + documented password
bin/dev                   # Procfile.dev: web + css + solid_queue worker
```

Seed: one teacher for local use. Document password in `db/seeds.rb` / README.

---

## 15. Explicit non-goals in code

- Multi-tenant school hierarchy, roles matrix, parent accounts
- Emailing links to students (clipboard copy only)
- SPA / Next.js / separate JSON API for MVP teacher UI
- Redis requirement (Solid Trifecta on Postgres instead)
- AI providers, presence heartbeats, proctoring (later phases only)
- Multi-correct MCQ, file uploads, coding questions
- Publishing answer keys to students after submit

---

## 16. Definition of done (MVP engineering)

- Migrations + Solid Trifecta installed; seed works.
- Teacher manages roster/classes/tests/assignments via Hotwire UI.
- Students take tests via links with timer + attempts basics.
- Teacher grades and sees history.
- PRD §5.3 checklist passed manually.
- Core lifecycle + scoring covered by Minitest.
- README with setup (`bin/setup`, `bin/dev`).

When MVP is done, implement 1.1 against §12 without rewriting the domain model.
