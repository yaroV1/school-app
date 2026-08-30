# Tests Platform

Teacher-owned tests app (Rails 8 + Hotwire + Solid Queue/Cache/Cable + SQLite). The schema supports
multiple teacher accounts; every teacher-owned query is scoped by owner.

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
- Password: `password1234`

Seed loads demo **Classes**, **Students**, **Subjects**, and **Tests** (with sample access links printed in the console). Re-run anytime with `bin/rails db:seed`, or wipe and reload with `bin/rails db:reset`.

## MVP + 1.1 flow

1. Sign in → create a **Class** → add **Students** and **Subjects** from the class page
2. From a subject, create a **Test**, add questions (MCQ / short / open / ordering / matching / source),
   set an optional availability window, **Publish**
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

## Backups

`BackupDatabaseJob` runs nightly from `config/recurring.yml` and keeps the last 7 snapshots in
`storage/backups/`. Only the **primary** database is copied — cache, queue and cable are all
rebuildable. Take one by hand before anything risky:

```bash
bin/rails db:backup                                    # locally
bin/kamal app exec --reuse "bin/rails db:backup"       # on the server
```

Snapshots are written with `VACUUM INTO`, not `cp`: under WAL the `.sqlite3` file on its own is
not a complete database, so a plain file copy silently loses the most recent commits.

### Restoring

The app must not be running — a live process holds its own WAL and will overwrite what you put
back.

```bash
bin/kamal app stop
bin/kamal app exec --reuse "bash -c '
  cd storage &&
  cp production.sqlite3 production.sqlite3.before-restore &&
  rm -f production.sqlite3-wal production.sqlite3-shm &&
  cp backups/primary-<STAMP>Z.sqlite3 production.sqlite3
'"
bin/kamal app boot
```

Deleting `-wal` and `-shm` is the step people skip: a stale write-ahead log left beside a restored
database replays over it and undoes the restore.

### What this does not cover

The snapshots sit on the same Docker volume as the database, so they protect against a bad
migration, a wrong bulk edit or a corrupted database — **not** against losing the volume or the
server. Copy them somewhere else on a schedule; until you do, a lost server is still lost grades.

```bash
# from your own machine
scp -r <server>:/var/lib/docker/volumes/school_app_storage/_data/backups ./
```

## Tests

```bash
bin/rails test
```

## Notes

- Domain model uses `Exam` (table `exams`) to avoid clashing with Minitest’s `Test`; UI and routes still say **Tests** (`/tests`).
- Student-facing controllers live under the `Take` namespace (not `Student`) so they don’t clash with the `Student` model. URLs remain `/t/:token`.
- Agent rules for Claude Code, Cursor, and Codex live in `docs/agent-rules.md`.
