import '../../../models/models.dart';

/// FR-1 / FR-2: 自分が参加者の予定を見落としにくくするため、表示上は先頭へ寄せる。
///
/// 「自分に関連する予定」は `participantIds` にログイン中 uid が含まれる予定として扱う。
/// 参加者機能導入前の空 `participantIds` は creator にフォールバックせず、既存順序だけで並べる。
List<Event> orderEventsForDisplay(List<Event> events, String? currentUid) {
  return List<Event>.of(events)..sort(
    (first, second) => compareEventsForDisplay(first, second, currentUid),
  );
}

int compareEventsForDisplay(Event first, Event second, String? currentUid) {
  final firstIsMine = _isCurrentUserParticipant(first, currentUid);
  final secondIsMine = _isCurrentUserParticipant(second, currentUid);
  if (firstIsMine != secondIsMine) {
    return firstIsMine ? -1 : 1;
  }
  if (first.allDay != second.allDay) {
    return first.allDay ? -1 : 1;
  }
  final startComparison = first.startAt.compareTo(second.startAt);
  if (startComparison != 0) {
    return startComparison;
  }
  return first.id.compareTo(second.id);
}

bool _isCurrentUserParticipant(Event event, String? currentUid) {
  return currentUid != null && event.participantIds.contains(currentUid);
}
