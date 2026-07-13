import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/version_check_provider.dart';
import '../data/release_info_repository.dart';

/// 更新履歴（過去のリリースノート）を新しい順に表示する画面（FR-7 / Issue #96）。
///
/// 起動時のお知らせダイアログは 1 回きりで、閉じると内容に到達できないため、
/// 設定画面からいつでも見返せるようにする。表示は Firestore のローカルキャッシュ
/// 起点（NFR-3）。
class ReleaseHistoryScreen extends ConsumerWidget {
  const ReleaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(releaseHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('更新履歴')),
      body: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const _CenteredMessage('更新履歴を取得できませんでした。通信環境を確認してもう一度お試しください。'),
        data: (releases) {
          if (releases.isEmpty) {
            return const _CenteredMessage('更新履歴はまだありません。');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: releases.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ReleaseTile(releases[index]),
          );
        },
      ),
    );
  }
}

class _ReleaseTile extends StatelessWidget {
  const _ReleaseTile(this.release);

  final ReleaseInfo release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final publishedAt = release.publishedAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'v${release.version}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              if (publishedAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${publishedAt.year}年${publishedAt.month}月${publishedAt.day}日',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            release.notes.isEmpty ? '（変更点の記載はありません）' : release.notes,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
