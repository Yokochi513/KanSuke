---
name: implement-kansuke-issue
description: Implement a KanSuke GitHub Issue end to end from its acceptance criteria. Use when asked to implement, fix, or complete an Issue in the KanSuke repository while following AGENTS.md, canonical docs, branch and scope rules, local validation, and commit or PR requirements.
---

# Implement a KanSuke Issue

## Workflow

1. Read `AGENTS.md` completely.
2. Fetch the requested Issue with `gh issue view <number>` and record its acceptance criteria, scope, exclusions, references, and validation commands.
3. Read the relevant canonical documents under `docs/`. Treat them as read-only specifications.
4. Inspect `git status`, preserve unrelated changes, and use the branch requested by the user or required by `AGENTS.md`.
5. Map every acceptance criterion to a code change or verification, then implement only that scope.
6. Format and run every validation required by the Issue and `AGENTS.md`.
7. Review the final diff for generated artifacts, secrets, specification edits, and unmet criteria.
8. Commit only when requested and report the commit hash and validation results.

## Operating Rules

Follow these rules:

- Do not edit canonical documents unless the user explicitly requests a specification change.
- Do not add Firebase, Riverpod, or other dependencies outside the Issue scope.
- Stop and report ambiguity instead of inventing missing product behavior.
- Never commit credentials, generated build outputs, or unrelated user changes.

## Flutter Validation

Run `flutter pub get`, `flutter analyze`, `dart format .`, `dart format --output=none --set-exit-if-changed .`, and `flutter test`.

If Flutter stalls before output, inspect Flutter/Dart processes and the SDK cache lock. The SDK may require permission to write its cache.

Before handoff, report the satisfied acceptance criteria, exact validation results, intentionally uncommitted files, and commit hash or PR URL.
