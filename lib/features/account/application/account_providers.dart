import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_providers.dart';
import '../data/account_deletion_repository.dart';

/// アカウント削除（退会、Issue #102）の経路。Callable Function を呼ぶ。
final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => FunctionsAccountDeletionRepository(
    functions: ref.watch(functionsProvider),
  ),
);
