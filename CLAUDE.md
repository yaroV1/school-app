# school-app

Teacher-owned tests app. Teachers sign in, build tests under a subject, and assign them. Students have no
accounts: they get a unique `/t/:token` link, take the test, and never authenticate. Rails 8.1, Hotwire
(Turbo + Stimulus), importmap, Propshaft, Tailwind, Minitest, SQLite — four files in production, Solid
Queue / Cache / Cable, no Redis, no Postgres. Ukrainian UI.

## AGENTS.md is canonical

`AGENTS.md` at the repo root is the agent contract. Read it before your first edit in a session. Follow it
for naming, style, security, quality, git, and when to ask. Do not restate those rules here. If this file
and `AGENTS.md` disagree, `AGENTS.md` wins.

## Working principles — as review tests

`AGENTS.md` states the rules; these are the tests for whether a diff honors them.

Run them after `bin/rails test` is green and before you report the change done. Write one line per test
naming the evidence — the second caller, the precedent file, the deleted code, the sanitizer line, the
ownership scope. If you cannot write the line, the diff is not done.

On the `/implement-prd` path these are carried by the review fan-out instead: the reviewers apply them,
the implementing agent does not repeat them.

**KISS.** If the diff adds a class, module, or service, name the second caller, the security boundary, or
the nontrivial domain logic that justifies it. If you can name none of the three, inline it. If it adds an
option or flag, name the caller that passes the non-default value.

**The Rails way.** Point at an existing file in this repo that the change resembles. A pattern with no
precedent here needs a stated reason. New behavior maps onto the nouns in `AGENTS.md` § Naming and
`db/schema.rb`, or it is probably the wrong shape.

**Clean code.** Describe each new method in one sentence with no "and". Names come from the domain
vocabulary in `AGENTS.md` § Naming; a reader who knows the domain should not need the body to guess what a
name means. No user-visible string literals in `.rb` or `.erb` — grep the diff for Cyrillic. If the diff
adds code to an existing file and deletes none, name the code the new path replaces, or state in one line
why the old path still has callers. Additive-only changes to existing behavior are how this codebase grows
a second way to do one thing.

**Security.** For any diff on a student-facing path, name the line that stops the answer key from reaching
the response. For any teacher-facing query, name the ownership scope. If the diff adds a param, name the
`permit` list it lands in. If it adds an export, a log line, a fixture, or a broadcast, state whether an
`access_token` can reach it and name the assertion that proves it cannot. "The UI never links to it" is
not an answer — `/t/:token` is public. Rules themselves: `AGENTS.md` § Security.

## Where things are

- Models: `app/models/` · schema in `db/schema.rb`
- Services: `app/services/` — read the directory before adding one
- Teacher controllers: `app/controllers/` · auth in `app/controllers/concerns/authentication.rb`
- Student controllers: `app/controllers/take/` · views in `app/views/take/`
- Question editor: `app/views/exams/show.html.erb` (`app/views/questions/` holds partials only)
- Stimulus: `app/javascript/controllers/` · pins in `config/importmap.rb`
- Strings: `config/locales/uk.yml`
- Routes: `config/routes.rb`
- Tests: `test/integration/` (`mvp_flow_test.rb` is the spine), `test/services/`, `test/models/`
- Jobs: `app/jobs/` · plan: `docs/TECHNICAL_PLAN.md`
- PRDs: `prd/` — see `prd/README.md` for the three stages

## Skills

Use `/prd` if the change does any of: touches `db/schema.rb`; adds a route or a controller action; adds or
changes a question type or a scoring rule; touches both a teacher-facing and a student-facing path; or
needs more than one commit to keep the suite green. None of those: just do it.

- `/prd` — writes `prd/_to_refine/<name>/project.md`. Writes no code, commits nothing.
- `/implement-prd` — executes a PRD already in `prd/backlog/`. It refuses `prd/_to_refine/`. It commits
  once per completed task under the carve-out in `AGENTS.md` § Git; the scope and the limits are in
  `.claude/skills/implement-prd/SKILL.md` § Git authorization.

## Quality gate

Authority is `AGENTS.md` § Quality — read it for when each command is required. Never report a check as
passing without running it.

```
bin/rails test
bin/rubocop
bin/importmap audit
bin/ci
```

Also available, and not governed by `AGENTS.md` § Quality except as steps inside `bin/ci`:

```
bin/brakeman        # when the diff touches anything under app/
bin/bundler-audit   # when the diff touches Gemfile or Gemfile.lock
```

How `bin/ci` differs from `.github/workflows/ci.yml`: `AGENTS.md` § Quality.
