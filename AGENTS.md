# Repository guidance for coding agents

This file applies to the entire repository. It contains durable engineering
rules, not temporary phase or branch status.

## Project context and decision sources

List & Split is an Android/iOS Flutter application for collaborative active
lists, reusable templates, mutual friendships and community, persistent
notifications, and optional expense-ledger functionality.

Before planning feature work, read the relevant source documents:

- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md): agreed user-facing behavior.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): technical boundaries.
- [`docs/DATA_MODEL.md`](docs/DATA_MODEL.md): conceptual entities and invariants.
- [`docs/DECISIONS.md`](docs/DECISIONS.md): accepted and open decisions.
- [`docs/ROADMAP.md`](docs/ROADMAP.md): delivery order and phase gates.

Apply this decision hierarchy:

1. The current user task has priority.
2. Accepted decisions in `docs/DECISIONS.md` are authoritative durable decisions.
3. The product, architecture, and data-model documents provide the relevant
   contract.
4. The roadmap controls planned sequencing, not implementation status.
5. If documents conflict or a relevant decision remains open, do not silently
   choose behavior affecting authorization, money, privacy, copying, retention,
   concurrency, or irreversible schema. Report or resolve it first.

When an accepted decision changes, update every affected source document in the
same pull request as the implementation.

## Start safely

- Inspect `git status`, the active branch, and the relevant files before editing.
- Preserve user-created work. Do not overwrite, revert, or reformat unrelated
  changes.
- Keep the diff scoped to the task; do not add speculative abstractions or empty
  feature scaffolding.
- Never commit credentials, tokens, passwords, signing material, `.env` files, or
  generated build output.

## Repository structure

- `lib/main.dart`: process entry point and top-level bootstrapping.
- `lib/app/`: application composition, router, themes, and app-wide providers.
- `lib/core/`: small, genuinely cross-feature primitives and infrastructure
  contracts. Do not turn it into a catch-all.
- `lib/l10n/`: ARB localization sources. Regenerate localization output with
  `flutter gen-l10n`; do not hand-edit generated files.
- `lib/features/<feature>/`: feature-first code. Keep UI/view models, domain
  concepts, and data implementations within the owning feature.
- `test/`: unit and widget tests, mirroring production code where practical.
- `supabase/`: local Supabase configuration and migration history.
- `docs/`: product, architecture, data-model, roadmap, and decision records.
- `.github/workflows/`: CI only; workflows must use stable, reproducible commands.

## Architecture boundaries

- Use MVVM-style presentation: widgets render state and emit user intent; Riverpod
  view models/providers coordinate use cases and state.
- Repositories are the application's data source of truth. UI and view models must
  not call Supabase, SQLite, or other transports directly.
- Keep backend DTOs and persistence details behind repository boundaries. Domain
  behavior must be testable without a live backend.
- Use Riverpod for state management and dependency injection, and `go_router` for
  navigation and future deep links.
- Keep the app runnable without backend credentials until a task explicitly adds
  an authenticated/backend-dependent flow.
- Local SQLite is a future cache beneath repositories, not a second source of
  truth. Do not introduce it before its synchronization rules are decided.
- Represent money only as integer minor units. Never use floating-point monetary
  values. Balance and debt computation belongs on the server and requires unit
  tests.
- Treat generated Freezed/JSON files as generated output: change source files and
  regenerate rather than hand-editing generated code.

## Standard checks

Run from the repository root:

```text
flutter pub get
dart format .
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
```

When generation is used, run:

```text
dart run build_runner build --delete-conflicting-outputs
```

For platform-affecting changes, also run the relevant build when the local SDK is
healthy, for example `flutter build apk --debug`. Report tooling blockers; do not
weaken checks to make them pass.

## Test expectations

- Add or update tests with every behavior change and regression fix.
- Unit-test business rules independently of Flutter UI and live services.
- Payment tests must cover integer arithmetic, exact-share validation, equal-split
  remainders, settlements, balances, and debt simplification once those rules are
  implemented.
- Test template snapshot/copy independence, membership and invitation transitions,
  authorization boundaries, repository behavior, and view-model state transitions
  when those capabilities are introduced.
- Keep at least one meaningful widget smoke test for application startup and the
  foundation screen.

## Git and pull requests

- Work on a task branch; do not commit directly to `main` unless the user
  explicitly authorizes repository initialization.
- Use the branch authorized for the current task.
- Use conventional commits and keep commits focused. Review staged content before
  committing.
- Never force-push. Push only the intended working branch, and only when the task
  authorizes publishing.
- Open pull requests as drafts unless the user explicitly requests otherwise.
- Never merge or auto-merge a pull request. Do not modify unrelated branches.
- Before handoff, review the complete diff for identifiers, secrets, generated
  artifacts, unrelated edits, and documentation that overstates implementation.

## Supabase and security

- Git-committed migrations are the schema source of truth. Do not make
  Dashboard-only schema changes.
- Do not introduce or alter business schema unless the current task explicitly
  authorizes it. Resolve and record the relevant decisions first, then implement
  schema changes through reviewed migrations with RLS and tests.
- Enable Row Level Security on every application table in the migration that
  creates it. Add least-privilege policies and test allowed and denied cases.
- Derive access from `auth.uid()` and server-validated relationships. Never trust
  a client-supplied owner, member, payer, or recipient identity.
- Prefer invoker-rights database functions. If a `security definer` function is
  necessary, pin its `search_path`, qualify objects, minimize grants, and test it
  as an authorization boundary.
- Use compile-time environment values such as `--dart-define` for public client
  configuration. Commit placeholders only.
- Never put a Supabase service-role key or any privileged secret in Flutter. Only
  public/anonymous or publishable client keys are valid in a client build.
- Never run destructive operations against a linked remote database, including
  reset, drop, truncate, or destructive repair commands. Verify the target before
  local reset operations, and require explicit task authorization before applying
  reviewed migrations remotely.
- Do not create production or Firebase projects unless a later task explicitly
  authorizes them.

## Definition of done

A change is done only when it is scoped, formatted, analyzed, tested in proportion
to risk, documented where behavior or decisions changed, and reviewed for security
and accessibility. Relevant checks must pass, or the exact external blocker must
be reported. Product documentation must label planned behavior as planned rather
than claiming it exists.
