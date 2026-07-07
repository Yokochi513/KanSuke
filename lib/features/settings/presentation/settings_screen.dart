import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme.dart';
import '../../../core/color_utils.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../application/notification_permission.dart';

/// フィードバック用 Google フォームの URL（tools/feedback-to-issue 参照）。
const _feedbackFormUrl = 'https://forms.gle/4h35EcT2Deqq8FsM6';

/// 設定画面（FR-2 / FR-5 / NFR-4、基本設計 §6.1・§2.2）。
///
/// 自分の識別色の変更、通知許可の状態表示・要求導線、サインアウトを提供する。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _SectionHeader('自分の名前'),
          const _NameSection(),
          const Divider(),
          const _SectionHeader('自分の色'),
          const _ColorSection(),
          const Divider(),
          const _SectionHeader('通知'),
          const _NotificationSection(),
          const Divider(),
          const _SectionHeader('フィードバック'),
          const _FeedbackSection(),
          const Divider(),
          const _SignOutSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// 自分の表示名を変更する（本人のみ更新可、FR-2 / §2.2）。
class _NameSection extends ConsumerStatefulWidget {
  const _NameSection();

  @override
  ConsumerState<_NameSection> createState() => _NameSectionState();
}

class _NameSectionState extends ConsumerState<_NameSection> {
  final _controller = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String uid) async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).updateName(uid, name);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(currentUidProvider);
    final currentName = ref.watch(currentUserProvider).asData?.value?.name;
    if (!_initialized && currentName != null) {
      _controller.text = currentName;
      _initialized = true;
    }
    final canSave = uid != null && !_saving;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: canSave,
              decoration: const InputDecoration(labelText: '名前'),
              onSubmitted: canSave ? (_) => _save(uid) : null,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: canSave ? () => _save(uid) : null,
          ),
        ],
      ),
    );
  }
}

/// 自分の識別色を選ぶ（本人のみ更新可、FR-2 / §2.2）。
class _ColorSection extends ConsumerWidget {
  const _ColorSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final currentColorHex = ref.watch(currentUserProvider).asData?.value?.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final color in MemberColors.palette)
            _ColorSwatch(
              color: color,
              selected:
                  currentColorHex != null &&
                  colorFromHex(currentColorHex).toARGB32() == color.toARGB32(),
              onTap: uid == null
                  ? null
                  : () => ref
                        .read(userRepositoryProvider)
                        .updateColor(uid, hexFromColor(color)),
            ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}

/// 通知許可の状態表示と要求導線（実トークン登録は #13）。
class _NotificationSection extends ConsumerWidget {
  const _NotificationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permission = ref.watch(notificationPermissionProvider);
    final statusLabel = permission.asData?.value.label ?? '確認中…';

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('通知の許可'),
          subtitle: Text('状態: $statusLabel'),
          trailing: FilledButton.tonal(
            onPressed: permission.isLoading
                ? null
                : () => ref
                      .read(notificationPermissionProvider.notifier)
                      .request(),
            child: const Text('許可をリクエスト'),
          ),
        ),
      ],
    );
  }
}

/// 不具合報告・要望を Google フォームから送ってもらう導線。
class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.feedback_outlined),
      title: const Text('ご意見・不具合報告'),
      subtitle: const Text('アンケートフォームを開きます'),
      trailing: const Icon(Icons.open_in_new),
      onTap: () => launchUrl(
        Uri.parse(_feedbackFormUrl),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}

class _SignOutSection extends ConsumerWidget {
  const _SignOutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: OutlinedButton.icon(
        onPressed: () async {
          // 先に元画面へ戻してからサインアウトする（未認証で設定画面を残さない）。
          Navigator.popUntil(context, (route) => route.isFirst);
          await ref.read(authActionControllerProvider.notifier).signOut();
        },
        icon: const Icon(Icons.logout),
        label: const Text('サインアウト'),
      ),
    );
  }
}
