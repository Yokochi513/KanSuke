import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/application/event_ordering.dart';
import 'package:kansuke/models/models.dart';

Event _event({
  required String id,
  required DateTime start,
  List<String> participants = const ['other'],
  int priority = defaultEventPriority,
  bool allDay = false,
}) {
  return Event(
    id: id,
    title: id,
    creatorId: participants.first,
    participantIds: participants,
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    allDay: allDay,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const {},
    updatedBy: participants.first,
    createdAt: start,
    updatedAt: start,
    deleted: false,
    calendarId: 'calendar-1',
    priority: priority,
  );
}

void main() {
  final morning = DateTime.utc(2026, 7, 27, 1);
  final noon = DateTime.utc(2026, 7, 27, 3);

  List<String> idsOf(List<Event> events, String? uid) =>
      orderEventsForDisplay(events, uid).map((event) => event.id).toList();

  group('orderEventsForDisplay', () {
    test('自分が参加する予定を先頭へ寄せる（FR-1 / FR-2）', () {
      final ordered = idsOf([
        _event(id: 'other', start: morning),
        _event(id: 'mine', start: noon, participants: const ['me']),
      ], 'me');

      expect(ordered, ['mine', 'other']);
    });

    // Issue #176: 優先度（1 が最重要）。
    test('優先度を上げた予定は、自分が参加していなくても先に並ぶ', () {
      final ordered = idsOf([
        _event(id: 'summer', start: morning),
        _event(id: 'openschool', start: noon, priority: 1),
      ], 'me');

      expect(ordered, ['openschool', 'summer']);
    });

    test('優先度は「自分の予定」より下の軸', () {
      final ordered = idsOf([
        _event(id: 'important-other', start: morning, priority: 1),
        _event(id: 'mine', start: noon, participants: const ['me']),
      ], 'me');

      expect(ordered, ['mine', 'important-other']);
    });

    test('優先度を下げた予定は既定の予定より後ろへ回る', () {
      final ordered = idsOf([
        _event(id: 'low', start: morning, priority: 9),
        _event(id: 'default', start: noon),
      ], 'me');

      expect(ordered, ['default', 'low']);
    });

    test('優先度が同じなら従来どおり終日→開始日時の順', () {
      final ordered = idsOf([
        _event(id: 'later', start: noon, priority: 3),
        _event(id: 'earlier', start: morning, priority: 3),
        _event(id: 'allday', start: noon, priority: 3, allDay: true),
      ], 'me');

      expect(ordered, ['allday', 'earlier', 'later']);
    });

    test('未サインイン（uid が null）でも優先度で並ぶ', () {
      final ordered = idsOf([
        _event(id: 'default', start: morning),
        _event(id: 'high', start: noon, priority: 1),
      ], null);

      expect(ordered, ['high', 'default']);
    });
  });
}
