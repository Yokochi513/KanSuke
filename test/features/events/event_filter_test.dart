import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/application/event_filter.dart';
import 'package:kansuke/models/models.dart';

/// テスト用のカレンダー ID（本番の ID は UUID。特別扱いされる固定 ID は無い）。
const testCalendarId = 'test-calendar';

Event _event({
  required String id,
  String creator = 'me',
  List<String>? participants,
}) {
  return Event(
    id: id,
    title: '予定$id',
    creatorId: creator,
    participantIds: participants ?? [creator],
    startAt: DateTime(2026, 7, 11),
    endAt: DateTime(2026, 7, 11),
    allDay: false,
    type: EventType.confirmed,
    memo: '',
    reminderOffsets: const [],
    updatedBy: creator,
    createdAt: DateTime(2026, 7, 11),
    updatedAt: DateTime(2026, 7, 11),
    deleted: false,
    calendarId: testCalendarId,
  );
}

void main() {
  final papa = _event(id: 'a', participants: ['papa']);
  final mama = _event(id: 'b', participants: ['mama']);
  final kids = _event(id: 'c', participants: ['papa', 'kodomo']);

  test('未選択（空集合）なら全件を返す', () {
    final events = [papa, mama, kids];
    expect(filterEventsByMembers(events, const {}), same(events));
  });

  test('選択メンバーを含む予定だけに絞る', () {
    final result = filterEventsByMembers([papa, mama, kids], {'mama'});
    expect(result, [mama]);
  });

  test('複数選択はいずれかを含む予定を返す（OR 条件）', () {
    final result = filterEventsByMembers(
      [papa, mama, kids],
      {'mama', 'kodomo'},
    );
    // mama を含む予定と、kodomo を含む予定（kids）の両方。
    expect(result, [mama, kids]);
  });

  test('該当なしなら空を返す', () {
    final result = filterEventsByMembers([papa, mama, kids], {'unknown'});
    expect(result, isEmpty);
  });

  test('参加者未設定の予定は作成者（memberIds）で絞り込める', () {
    // participantIds が空でも memberIds は作成者へフォールバックする。
    final legacy = _event(id: 'd', creator: 'papa', participants: const []);
    final result = filterEventsByMembers([legacy], {'papa'});
    expect(result, [legacy]);
  });
}
