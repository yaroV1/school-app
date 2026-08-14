# Tests Platform

Single-teacher tests app (Rails 8 + Hotwire + Solid Queue/Cache/Cable + SQLite).

Students take tests via unique access links (no student accounts). Teachers manage roster, classes, tests, grading, and history.

## Setup

```bash
bin/setup
bin/rails db:seed
bin/dev
```

Open [http://localhost:3000](http://localhost:3000).

**Teacher login (seed):**
- Email: `teacher@example.com`
- Password: `password123`

Seed loads demo **Classes**, **Students**, and **Tests** (with sample access links printed in the console). Re-run anytime with `bin/rails db:seed`, or wipe and reload with `bin/rails db:reset`.

## MVP + 1.1 flow

1. Sign in → create **Students** and optional **Classes**
2. Create a **Test**, add MCQ / short / open questions, set optional availability window, **Publish**
3. **Assign / links** → copy per-student URLs (`/t/...`); bulk revoke supported
4. Open **Live board** during the session (polls every ~4s; class filter; new-submit toast)
5. Student opens link → Start → answer (autosave + server countdown) → Submit
6. Teacher opens **Results** → grade short/open → finalize
7. Student history is on each student page

## Stack

- Ruby on Rails 8, Hotwire (Turbo + Stimulus), Tailwind
- SQLite (development/test/production-ready for personal use)
- Solid Queue, Solid Cache, Solid Cable
- Rails 8 authentication (session + `has_secure_password`)

## Tests

```bash
bin/rails test
```

## Notes

- Domain model uses `Exam` (table `exams`) to avoid clashing with Minitest’s `Test`; UI and routes still say **Tests** (`/tests`).
- Student-facing controllers live under the `Take` namespace (not `Student`) so they don’t clash with the `Student` model. URLs remain `/t/:token`.
- Product phases beyond MVP (live status board, AI draft grading, live progress) are described in `docs/TECHNICAL_PLAN.md`.
