# Codex 実装運用フロー

> Claude Code が GitHub Issue を起こし、**Codex CLI（ローカル）**が実装する運用の手順書。
> リポジトリ文脈は [AGENTS.md](../../AGENTS.md)、タスクの書式は [Issueテンプレート](../../.github/ISSUE_TEMPLATE/codex-task.md) を参照。

## 役割分担

| 担当 | やること |
| --- | --- |
| **Claude Code** | 仕様（docs/）を読み、小さなタスク単位で Issue を起票。粒度・受け入れ条件・検証方法を明確化。実装レビュー補助。 |
| **人間（あなた）** | Issue を確認し、Codex CLI を起動して実装させる。PR をレビュー・マージ。仕様判断。 |
| **Codex CLI** | Issue 1件を 1ブランチ・1PR で実装。AGENTS.md のルールに従う。 |

## 基本原則

- **1 Issue = 1 PR**。小さく完結させる。
- Issue は**それ単体で実装できる**よう自己完結させる（Codex は会話文脈を引き継げない）。
- 仕様の正典は `docs/`。Issue には docs の該当節へのリンクを必ず入れる。
- 仕様変更が要る場合、Codex は実装せず Issue にコメントを残す → 人間が判断。

## フロー

```
1. Claude Code が Issue を起票（codex-task テンプレートに沿う）
   └─ gh issue create で作成。labels: codex を付与
        ↓
2. 人間が Issue を確認（粒度・受け入れ条件をチェック）
        ↓
3. 人間がローカルで Codex CLI を起動して実装を依頼
   例) codex "Issue #12 を実装して。AGENTS.md と Issue 本文の受け入れ条件に従うこと"
        ↓
4. Codex がブランチ feat/12-xxx を作成 → 実装 → flutter analyze / test → PR 作成
        ↓
5. 人間（必要なら Claude Code 補助）が PR レビュー → マージ
        ↓
6. Issue クローズ（PR に "Closes #12" を入れておけば自動）
```

## Codex CLI への依頼テンプレート（コピペ用）

```
Issue #<番号> を実装してください。
- まず AGENTS.md と Issue 本文を読むこと
- ブランチ feat/<番号>-<スラッグ> を切ること
- Issue の「受け入れ条件」をすべて満たすこと
- 完了前に flutter analyze と flutter test を通すこと
- 仕様に迷ったら推測せず止めて確認すること
```

## Issue 起票時のチェックリスト（Claude Code 用）

- [ ] スコープが 1 PR で終わる大きさか
- [ ] 「やらないこと（スコープ外）」を書いたか
- [ ] docs の該当節へのリンクがあるか
- [ ] 受け入れ条件が検証可能な形か
- [ ] 依存 Issue を明記したか
- [ ] `codex` ラベルを付けたか

## ラベル運用

| ラベル | 用途 |
| --- | --- |
| `codex` | Codex に実装させる対象タスク |
| `blocked` | 依存未完で着手不可 |
| `needs-spec` | 仕様の確認待ち（人間判断が要る） |
| `area:flutter` / `area:functions` / `area:firebase` | 領域 |
