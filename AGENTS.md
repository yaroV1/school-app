# school-app

Teacher-owned tests app: students have no accounts and enter via unique `/t/:token` links. The schema allows multiple `User` teacher records; always scope by owner. Rails 8, Hotwire, Minitest, SQLite, Ukrainian UI.

This file is the canonical agent contract. `.cursor/rules/` should point here, not duplicate it.

## Naming (do not invent alternatives)

- Model/table: `Exam` / `exams`. UI and routes: `/tests` (`as: :tests`). An exam belongs to a `Subject`; a subject belongs to a `ClassGroup`. Create and list tests from the subject page. Students stay on the class (shared across subjects).
- Students belong to a teacher and appear in classes via `class_memberships`. Add students from the class page; add subjects from the class page (no top-level Students/Tests nav).
- Student-facing controllers: `Take::` (not `Student`). URLs stay `/t/:token`.
- Question types: `mcq`, `short_text`, `open`, `ordering`, `matching`, `source`.
- Auto-scored: MCQ, ordering (all-or-nothing), matching (partial). Teacher-scored: short_text, open, source.

## Style

- Follow Rails layout and copy nearby code. Prefer simple, explicit changes.
- Extract a service for nontrivial domain or security logic (existing: `Scoring`, `AttemptLifecycle`, `QuestionSanitizer`, `TokenGenerator`, `LiveBoard`, `LiveBroadcast`, `GradeLive`). Read `app/services/` and reuse before adding an eighth. Do not add layers “for SOLID.”
- New UI strings go in `config/locales/uk.yml`. Default locale is `uk`.
- Do not invent tables, columns, routes, or APIs. Check `db/schema.rb`, `config/routes.rb`, and existing code first.
- Check `Gemfile.lock` (and the gem version in use) before assuming third-party APIs.
- Do not edit `docs/TECHNICAL_PLAN.md` unless asked.

## Security

Do not leak **answer keys** to students (`QuestionSanitizer` / student-facing helpers). Students still need the visible content:

- MCQ: send option `id` + `text`. Never send `is_correct`.
- Ordering: send shuffled items. Never send the stored (correct) order as the display order.
- Matching: send left items and shuffled right items. Never send `question.config["pairs"]` (the answer key). Student **responses** may use `payload["pairs"]` / `payload["order"]` — that is not the key.
- Never send rubric or model answer.

Teacher data: scope through `Current.user` associations (`Current.user.exams.find`) **or** equivalent ownership joins (`Attempt.joins(assignment: :exam).where(exams: { teacher_id: Current.user.id })`). Do not load teacher resources by bare id.

Exception: `Take::` controllers are unauthenticated. They resolve `Assignment.find_by!(access_token: params[:token])`, then scope attempts/answers through that assignment. Do not add `Current.user` there.

Assignment tokens are secrets. Do not add them to application logs or commit them. `filter_parameters` redacts `params[:token]`; request paths like `/t/:token` still appear in HTTP logs — treat those logs as sensitive.

Strong params only. Do not `permit!`. Do not weaken CSRF, session cookies, or `has_secure_password`.

## Quality

After changing behavior:

1. Add or update Minitest coverage (extend `test/integration/mvp_flow_test.rb` and/or scoring/lifecycle tests). No coverage %.
2. `bin/rails test` must pass.
3. `bin/rubocop` (autocorrect only files you touched: `bin/rubocop -A path`).
4. There is **no JS style linter**. Run `bin/importmap audit` only when JS dependencies change.

`bin/ci` is a CI-style local check (RuboCop, audits, Brakeman, tests, seed replant). It is not identical to GitHub Actions: GitHub also runs system tests; `bin/ci` skips those and extra-checks seeds.

## Git

- Never `git commit` or `git push` unless the user explicitly asks in that message.
- Exception, and the only one: invoking `/implement-prd` **is** that explicit request, for commits only, for that run. Scope and limits: `.claude/skills/implement-prd/SKILL.md` § Git authorization. It never authorizes a push.
- Never `--no-verify`, force-push, or change git config.
- Remote is personal GitHub (`github.com-personal:yaroV1/school-app.git`). Do not use a work GitHub account.
- Some global gitignores exclude `/AGENTS.md`. Track it with `git add -f AGENTS.md`.

## When to ask vs inspect

- Ask if the request is ambiguous or the choice is hard to reverse (schema, auth, scoring rules, new question type behavior).
- If the codebase already has the answer, inspect it and proceed. Prefer one clarifying question over building the wrong feature.
