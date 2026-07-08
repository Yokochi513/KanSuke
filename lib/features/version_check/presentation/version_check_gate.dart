import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/version_check_provider.dart';

/// サインイン後の画面をラップし、起動時に新バージョン通知ダイアログを
/// 一度だけ表示する（FR-7）。
class VersionCheckGate extends ConsumerStatefulWidget {
  const VersionCheckGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<VersionCheckGate> createState() => _VersionCheckGateState();
}

class _VersionCheckGateState extends ConsumerState<VersionCheckGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final release = await ref.read(versionUpdateNoticeProvider.future);
    if (release == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新しいバージョンがあります'),
        content: Text(
          release.notes.isEmpty
              ? 'バージョン ${release.version} が公開されました。'
              : 'バージョン ${release.version}\n\n${release.notes}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
    await markVersionAsSeen(release.version);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
