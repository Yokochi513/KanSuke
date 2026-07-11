import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/events/application/event_grouping.dart';
import 'package:kansuke/models/models.dart';

Event _event({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
  String creator = 'me',
  List<String>? participants,
  EventType type = EventType.confirmed,
  String calendarId = defaultCalendarId,
}) {
  return Event(
    id: id,
    title: title,
    creatorId: creator,
    participantIds: participants ?? [creator],
    startAt: start,
    endAt: end,
    allDay: false,
    type: type,
    memo: '',
    reminderOffsets: const [],
    updatedBy: creator,
    createdAt: start,
    updatedAt: start,
    deleted: false,
    calendarId: calendarId,
  );
}

void main() {
  test('同名で期間が重なる予定は1グループに束ねる', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '旅行',
        creator: 'me',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 7),
      ),
      _event(
        id: 'b',
        title: '旅行',
        creator: 'mama',
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 8),
      ),
    ]);

    expect(groups, hasLength(1));
    final group = groups.single;
    expect(group.isMerged, isTrue);
    // 期間は和集合（7/5〜7/8）。
    expect(group.startAt, DateTime(2026, 7, 5));
    expect(group.endAt, DateTime(2026, 7, 8));
    // のべ参加者を重複排除（me・mama）。
    expect(group.memberIds, ['me', 'mama']);
    expect(group.participantCount, 2);
  });

  test('前の終了日+1に始まる隣接予定は束ねる', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '合宿',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 6),
      ),
      _event(
        id: 'b',
        title: '合宿',
        start: DateTime(2026, 7, 7),
        end: DateTime(2026, 7, 8),
      ),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.isMerged, isTrue);
  });

  test('空き日が1日以上ある同名予定は束ねない', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '帰省',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 6),
      ),
      // 7/6 の翌々日（間に 7/7 が空く）。
      _event(
        id: 'b',
        title: '帰省',
        start: DateTime(2026, 7, 8),
        end: DateTime(2026, 7, 9),
      ),
    ]);

    expect(groups, hasLength(2));
    expect(groups.every((group) => !group.isMerged), isTrue);
  });

  test('タイトルが違えば束ねない', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '旅行',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 7),
      ),
      _event(
        id: 'b',
        title: '出張',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 7),
      ),
    ]);

    expect(groups, hasLength(2));
  });

  test('タイトルは前後の空白を無視して比較する', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '旅行',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 6),
      ),
      _event(
        id: 'b',
        title: '  旅行  ',
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 7),
      ),
    ]);

    expect(groups, hasLength(1));
    expect(groups.single.isMerged, isTrue);
  });

  test('1件でも仮があればグループは仮扱い', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '旅行',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 6),
        type: EventType.confirmed,
      ),
      _event(
        id: 'b',
        title: '旅行',
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 7),
        type: EventType.tentative,
      ),
    ]);

    expect(groups.single.type, EventType.tentative);
  });

  test('日別の参加者は、その日実際に参加している人だけを表示順で返す', () {
    // 父 7/18〜8/23 に子 8/7〜8/16 が含まれるケース（開始日の誤解対策）。
    final group = groupEventsForMerge([
      _event(
        id: 'a',
        title: '夏休み',
        creator: 'papa',
        start: DateTime(2026, 7, 18),
        end: DateTime(2026, 8, 23),
      ),
      _event(
        id: 'b',
        title: '夏休み',
        creator: 'kodomo',
        start: DateTime(2026, 8, 7),
        end: DateTime(2026, 8, 16),
      ),
    ]).single;

    // 開始日（7/18）は父のみ。
    expect(
      activeMemberIdsPerDay(
        group,
        DateTime(2026, 7, 18),
        DateTime(2026, 7, 18),
      ),
      [
        ['papa'],
      ],
    );
    // 重なる期間（8/7）は父＋子（グループの表示順）。
    expect(
      activeMemberIdsPerDay(group, DateTime(2026, 8, 7), DateTime(2026, 8, 7)),
      [
        ['papa', 'kodomo'],
      ],
    );
    // 子が抜けた後（8/23）は再び父のみ。
    expect(
      activeMemberIdsPerDay(
        group,
        DateTime(2026, 8, 23),
        DateTime(2026, 8, 23),
      ),
      [
        ['papa'],
      ],
    );
  });

  test('別カレンダーの同名予定は束ねない', () {
    final groups = groupEventsForMerge([
      _event(
        id: 'a',
        title: '旅行',
        start: DateTime(2026, 7, 5),
        end: DateTime(2026, 7, 7),
        calendarId: 'cal-1',
      ),
      _event(
        id: 'b',
        title: '旅行',
        start: DateTime(2026, 7, 6),
        end: DateTime(2026, 7, 8),
        calendarId: 'cal-2',
      ),
    ]);

    expect(groups, hasLength(2));
  });
}
