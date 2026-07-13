import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../app/theme.dart';
import '../../../core/color_utils.dart';
import '../../auth/application/auth_state.dart';
import '../../users/application/user_providers.dart';
import '../../version_check/application/version_check_provider.dart';
import '../application/event_merge_provider.dart';
import '../application/notification_permission.dart';
import '../application/theme_mode_provider.dart';

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
          const _SectionHeader('表示テーマ'),
          const _ThemeModeSection(),
          const Divider(),
          const _SectionHeader('通知'),
          const _NotificationSection(),
          const Divider(),
          const _SectionHeader('カレンダー'),
          const _CalendarManagementSection(),
          const Divider(),
          const _SectionHeader('予定のまとめ表示'),
          const _EventMergeSection(),
          const Divider(),
          const _SectionHeader('フィードバック'),
          const _FeedbackSection(),
          const Divider(),
          const _SectionHeader('このアプリについて'),
          const _AppInfoSection(),
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          // 朱の細い縦棒を見出しの頭に置き、落款のような区切りにする。
          Container(width: 3, height: 14, color: scheme.secondary),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: scheme.primary),
          ),
        ],
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
    final currentColor = currentColorHex == null
        ? null
        : colorFromHex(currentColorHex);
    final selectedPaletteColor =
        currentColor != null &&
        MemberColors.palette.any(
          (paletteColor) => paletteColor.toARGB32() == currentColor.toARGB32(),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final color in MemberColors.palette)
            _ColorSwatch(
              key: ValueKey('member-color-${hexFromColor(color)}'),
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
          _CustomColorSwatch(
            color: currentColor ?? MemberColors.palette.first,
            selected: currentColor != null && !selectedPaletteColor,
            onTap: uid == null
                ? null
                : () => _showCustomColorPicker(
                    context,
                    ref,
                    uid,
                    currentColor ?? MemberColors.palette.first,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomColorPicker(
    BuildContext context,
    WidgetRef ref,
    String uid,
    Color initialColor,
  ) async {
    final userRepository = ref.read(userRepositoryProvider);
    final selectedColor = await showDialog<Color>(
      context: context,
      builder: (context) => _RgbColorPickerDialog(initialColor: initialColor),
    );
    if (selectedColor == null) {
      return;
    }
    await userRepository.updateColor(uid, hexFromColor(selectedColor));
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '色 ${hexFromColor(color)}',
      child: InkResponse(
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
          child: selected
              ? Icon(Icons.check, color: _foregroundForSwatch(color))
              : null,
        ),
      ),
    );
  }
}

class _CustomColorSwatch extends StatelessWidget {
  const _CustomColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: '好きな色を選ぶ',
      child: InkResponse(
        onTap: onTap,
        child: Container(
          key: const ValueKey('member-custom-color'),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: selected ? color : scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: Icon(
            selected ? Icons.check : Icons.palette_outlined,
            color: selected ? _foregroundForSwatch(color) : scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _RgbColorPickerDialog extends StatefulWidget {
  const _RgbColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_RgbColorPickerDialog> createState() => _RgbColorPickerDialogState();
}

class _RgbColorPickerDialogState extends State<_RgbColorPickerDialog> {
  late int _redValue;
  late int _greenValue;
  late int _blueValue;

  Color get _selectedColor =>
      Color.fromARGB(255, _redValue, _greenValue, _blueValue);

  @override
  void initState() {
    super.initState();
    final initialColorValue = widget.initialColor.toARGB32();
    _redValue = (initialColorValue >> 16) & 0xFF;
    _greenValue = (initialColorValue >> 8) & 0xFF;
    _blueValue = initialColorValue & 0xFF;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('色を選択'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 64,
              decoration: BoxDecoration(
                color: _selectedColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              alignment: Alignment.center,
              child: Text(
                hexFromColor(_selectedColor),
                style: TextStyle(
                  color: _foregroundForSwatch(_selectedColor),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _ColorChannelSlider(
              label: '赤',
              value: _redValue,
              activeColor: WashiColors.shu,
              onChanged: (value) => setState(() => _redValue = value),
            ),
            _ColorChannelSlider(
              label: '緑',
              value: _greenValue,
              activeColor: WashiColors.matsuba,
              onChanged: (value) => setState(() => _greenValue = value),
            ),
            _ColorChannelSlider(
              label: '青',
              value: _blueValue,
              activeColor: WashiColors.hanada,
              onChanged: (value) => setState(() => _blueValue = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selectedColor),
          child: const Text('決定'),
        ),
      ],
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color activeColor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 32, child: Text(label)),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value.toDouble(),
            label: value.toString(),
            activeColor: activeColor,
            onChanged: (sliderValue) => onChanged(sliderValue.round()),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(value.toString(), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

Color _foregroundForSwatch(Color color) {
  return color.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

/// 表示テーマを「自動（端末設定に従う）／和紙（ライト）／墨（ダーク）」から選ぶ。
///
/// 端末ローカルの設定のため、家族の他のメンバーの表示には影響しない。
class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(resolvedThemeModeProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              segments: [
                for (final mode in ThemeMode.values)
                  ButtonSegment(
                    value: mode,
                    icon: Icon(mode.icon),
                    label: Text(mode.label),
                    tooltip: mode.label,
                  ),
              ],
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  ref.read(themeModeProvider.notifier).select(selection.single),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '「自動」は端末のダークモード設定に従います。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 月表示のマージ表示（同名・期間が連なる予定を 1 本に束ねる）の ON/OFF
/// （Issue #76、FR-2 / FR-4）。
///
/// 暗黙グルーピングの誤爆に備えた保険として切り替えられるようにする。既定は ON。
/// 端末ローカルの設定のため、家族の他のメンバーの表示には影響しない。
class _EventMergeSection extends ConsumerWidget {
  const _EventMergeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(resolvedEventMergeEnabledProvider);

    return SwitchListTile(
      secondary: const Icon(Icons.merge_type),
      title: const Text('同じ予定をまとめる'),
      subtitle: const Text('同名で期間が重なる予定を月表示で1本に束ねます。'),
      value: enabled,
      onChanged: (value) =>
          ref.read(eventMergeEnabledProvider.notifier).setEnabled(value),
    );
  }
}

/// 通知許可の状態表示と要求導線（FR-5、Issue #13）。
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

/// カレンダーの新規作成・名前や参加者の編集画面への導線（FR-8）。
class _CalendarManagementSection extends StatelessWidget {
  const _CalendarManagementSection();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.calendar_month_outlined),
      title: const Text('カレンダー管理'),
      subtitle: const Text('作成・名前や参加者の編集'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, AppRoutes.calendarManagement),
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

/// インストール済みバージョンの表示と、更新履歴画面への導線（FR-7 / Issue #96）。
class _AppInfoSection extends ConsumerWidget {
  const _AppInfoSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).asData?.value;

    return ListTile(
      leading: const Icon(Icons.history),
      title: const Text('更新履歴'),
      subtitle: Text(version == null ? 'これまでの変更点を見る' : '現在のバージョン: $version'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pushNamed(context, AppRoutes.releaseHistory),
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
