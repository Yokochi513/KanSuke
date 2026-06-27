---
name: implement-kansuke-issue
description: Implement a KanSuke GitHub Issue end to end from its acceptance criteria. Use when asked to implement, fix, or complete an Issue in the KanSuke repository while following AGENTS.md, canonical docs, branch and scope rules, local validation, and commit or PR requirements.
---

# Implement a KanSuke Issue

## Workflow

1. Read `AGENTS.md` completely.
2. Fetch the requested Issue with `gh issue view <number>` and record its acceptance criteria, scope, exclusions, references (including the related `docs/` sections and FR-x / NFR-x numbers), and validation commands.
3. Read the relevant canonical documents under `docs/`. Treat them as read-only specifications.
4. Inspect `git status` and preserve unrelated changes. Create one branch for this Issue: `feat/<issue-number>-<short-english-slug>` for features, `fix/<issue-number>-<slug>` for fixes (or the branch the user requests).
5. Map every acceptance criterion to a code change or verification, then implement only that scope. Annotate implementation that satisfies a spec item with its FR-x / NFR-x number in a code comment or the PR body.
6. Format and run every validation required by the Issue and `AGENTS.md` (see Validation below).
7. Review the final diff for generated artifacts, secrets, specification edits, and unmet criteria.
8. Follow the `1 Issue = 1 branch = 1 PR` rule. Open a PR targeting `main` whose body lists the Issue number (`Closes #<number>`), a checklist of the satisfied acceptance criteria, and the exact validation commands run with their results. Commit and push only when requested; report the commit hash and PR URL.

## Operating Rules

Follow these rules:

- Do not edit canonical documents under `docs/`. If a spec change seems necessary, stop and leave a comment on the Issue (the `needs-spec` label applies) instead of implementing it.
- Do not introduce new dependencies beyond the Issue scope. Note: Riverpod is the mandated state management and `table_calendar` the month view per `AGENTS.md` — use them; just do not add unrelated packages.
- Stop and report ambiguity instead of inventing missing product behavior.
- Never commit credentials (`google-services.json`, `GoogleService-Info.plist`, production `.firebaserc` values, APNs keys, `*.keystore`), generated build outputs, or unrelated user changes.

## Validation

Flutter (run whenever Dart/Flutter code changes):

Run `flutter pub get`, `flutter analyze` (keep warnings at zero), `dart format .`, `dart format --output=none --set-exit-if-changed .`, and `flutter test`.

Cloud Functions (run only when `functions/` changes):

Run `npm --prefix functions ci`, `npm --prefix functions run lint`, and `npm --prefix functions test`.

If Flutter stalls before output, inspect Flutter/Dart processes and the SDK cache lock. The SDK may require permission to write its cache.

Before handoff, report the satisfied acceptance criteria, exact validation results, intentionally uncommitted files, and commit hash or PR URL.
