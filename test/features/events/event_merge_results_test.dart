import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/application/event_providers.dart';
import 'package:kansuke/models/models.dart';

/// Issue #170: カレンダーごとの購読結果を 1 本に合成するロジックの検証。
Event _event(String title, int hour, String calendarId) {
  final start = DateTime(2026, 7, 5, hour);
  return Event.create(
    title: title,
    creatorId: 'me',
    participantIds: const ['me'],
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const {},
    updatedBy: 'me',
    now: start,
    calendarId: calendarId,
  );
}

void main() {
  group('mergeEventResults（Issue #170）', () {
    test('複数カレンダーの予定を 1 本にまとめ、開始時刻順に並べる', () {
      final home = _event('わが家の予定', 13, 'home');
      final work = _event('しごとの予定', 9, 'work');

      final merged = mergeEventResults([
        AsyncValue.data([home]),
        AsyncValue.data([work]),
      ]);

      expect(
        [for (final event in merged.requireValue) event.title],
        ['しごとの予定', 'わが家の予定'],
      );
    });

    test('表示対象が無ければ空リストを返す', () {
      expect(mergeEventResults(const []).requireValue, isEmpty);
    });

    test('1 本でも値が届いていれば、その時点のぶんを返す（オフラインファースト）', () {
      final home = _event('わが家の予定', 9, 'home');

      final merged = mergeEventResults([
        AsyncValue.data([home]),
        const AsyncValue<List<Event>>.loading(),
      ]);

      expect(merged.hasValue, isTrue);
      expect(merged.requireValue, hasLength(1));
    });

    test('どれも値を持たないうちは loading', () {
      final merged = mergeEventResults(const [
        AsyncValue<List<Event>>.loading(),
        AsyncValue<List<Event>>.loading(),
      ]);

      expect(merged.isLoading, isTrue);
      expect(merged.hasValue, isFalse);
    });

    test('1 本でも失敗したらエラーを返す（黙って隠さない）', () {
      final home = _event('わが家の予定', 9, 'home');

      final merged = mergeEventResults([
        AsyncValue.data([home]),
        AsyncValue<List<Event>>.error('permission-denied', StackTrace.empty),
      ]);

      expect(merged.hasError, isTrue);
      expect(merged.error, 'permission-denied');
    });
  });
}
