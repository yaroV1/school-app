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

## Telegram delivery

Students can store an optional Telegram username alongside their name and email. Each class has one
bot invitation link on its **Students** tab. Students open it privately and press **Start**; the bot
matches the username within that class. The teacher verifies the account with the student and confirms
the request on the student's page. A username alone never grants access to test links.

After confirmation, **Assign / links** offers sending to all assigned students, selected rows, or one
student. Each message contains only that student's existing `/t/` link. Publishing does not send
anything. Confirmed numeric Telegram IDs survive username changes; disconnect before binding a
different account. Students without usernames must set one before onboarding.

### One-time bot setup

1. Create a dedicated bot using [@BotFather](https://t.me/BotFather). Use separate bots for development
   and production: Telegram allows only one webhook per bot.
2. Configure these Rails credentials with `bin/rails credentials:edit` (never commit plaintext tokens):

   ```yaml
   telegram:
     bot_token: <token from BotFather>
     bot_username: <bot username without @>
     webhook_secret: <random secret, e.g. openssl rand -hex 32>
     app_url: https://edubba.com.ua
   ```

   Environment variables `TELEGRAM_BOT_TOKEN`, `TELEGRAM_BOT_USERNAME`, `TELEGRAM_WEBHOOK_SECRET`, and
   `TELEGRAM_APP_URL` override credentials. `app_url` is the public HTTPS origin, not a request-derived
   hostname. In Kamal, credentials use the existing `RAILS_MASTER_KEY`; environment overrides need
   explicit forwarding in `config/deploy.yml` and `.kamal/secrets`.
3. Deploy the code/migration and restart with the configuration. Ensure Solid Queue is running
   (`SOLID_QUEUE_IN_PUMA` is already enabled in production).
4. **After approving the external configuration change**, run in the configured environment:

   ```bash
   RAILS_ENV=production bin/rails telegram:set_webhook
   # Or, from an authorized operator's machine:
   bin/kamal app exec --reuse "bin/rails telegram:set_webhook"
   ```

   This registers `/telegram/webhook` with a secret header, accepts only message updates, and does not
   discard pending updates. It never prints the bot token. The endpoint must be publicly reachable by
   Telegram over HTTPS; an authenticated development portal is not a production webhook endpoint.
5. Use a test student to complete Start → teacher confirmation → send → receive before inviting a class.

### Delivery status and retries

Refresh the assignment page to see **queued / sending / sent / failed**. Sent means Telegram accepted
the message, not that the student read it. Unconnected, archived and revoked assignments are skipped.
Messages are spaced one second apart within a batch. A Telegram rate limit or blocked bot is shown as
an error; unblock/start the bot or wait, then retry explicitly.

Double clicks and duplicate jobs are suppressed. Queued work rechecks the recipient, publication,
revocation and token before sending; regenerating a link clears its previous delivery status.
An already in-flight API request cannot be recalled. Timeouts are marked **result unknown**, not
automatically retried: Telegram has no idempotency key for `sendMessage`. Check with the student before
retrying to avoid duplicates. If a worker stops while queued/sending, the retry button becomes available
after five minutes. Check the worker first; resending all also repeats previously successful messages.

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

## Deploy

Production is one Docker container on a DigitalOcean droplet, deployed by Kamal from a GitHub Actions
job that runs only on a green `main`. Setup, secrets, backups, and the steps to add a domain are in
[`docs/deploy.md`](docs/deploy.md).

## Notes

- Domain model uses `Exam` (table `exams`) to avoid clashing with Minitest’s `Test`; UI and routes still say **Tests** (`/tests`).
- Student-facing controllers live under the `Take` namespace (not `Student`) so they don’t clash with the `Student` model. URLs remain `/t/:token`.
- Agent rules for Claude Code, Cursor, and Codex live in `docs/agent-rules.md`.
