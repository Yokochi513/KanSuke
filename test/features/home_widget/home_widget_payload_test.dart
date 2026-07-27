import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kansuke/features/home_widget/application/home_widget_payload.dart';
import 'package:kansuke/models/models.dart';

Event _event({
  required String id,
  required DateTime start,
  DateTime? end,
  String title = '予定',
  List<String> participants = const ['other'],
  bool allDay = false,
  EventType type = EventType.confirmed,
  int priority = defaultEventPriority,
}) {
  return Event(
    id: id,
    title: title,
    creatorId: participants.first,
    participantIds: participants,
    startAt: start,
    endAt: end ?? start.add(const Duration(hours: 1)),
    allDay: allDay,
    type: type,
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

User _user(String id, String color) {
  return User(
    id: id,
    name: id,
    email: '$id@example.com',
    color: color,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}

/// 日付キーで日を引く。
Map<String, Object?> _day(Map<String, Object?> payload, String date) {
  final days = (payload['days']! as List).cast<Map<String, Object?>>();
  return days.firstWhere((day) => day['date'] == date);
}

List<Map<String, Object?>> _entries(Map<String, Object?> payload, String date) {
  return (_day(payload, date)['entries']! as List).cast<Map<String, Object?>>();
}

void main() {
  // 端末ローカルの日付で切り出すため、テストのフィクスチャもローカル時刻で作る。
  final now = DateTime(2026, 7, 28, 9, 30);
  const today = '2026-07-28';
  const tomorrow = '2026-07-29';

  Map<String, Object?> build({
    required List<Event> events,
    Map<String, User> membersById = const {},
    String? currentUid,
    String? mergedBarColor,
  }) {
    return buildHomeWidgetPayload(
      events: events,
      membersById: membersById,
      now: now,
      currentUid: currentUid,
      mergedBarColor: mergedBarColor,
    );
  }

  List<Object?> datesOf(Map<String, Object?> payload) => [
    for (final day in (payload['days']! as List).cast<Map<String, Object?>>())
      day['date'],
  ];

  group('homeWidgetDayRange', () {
    test('今月のグリッド開始から翌月のグリッド終了までを覆う', () {
      // 2026-07-01 は水曜。その週の日曜は 6/28。
      // 2026-08-01 は土曜。その週の日曜は 7/26。そこから 6 週で 9/6 まで。
      final range = homeWidgetDayRange(now);

      expect(range.start, DateTime(2026, 6, 28));
      expect(range.end, DateTime(2026, 9, 6));
    });

    test('1日が日曜の月は、その日がグリッドの先頭になる', () {
      // 2026-11-01 は日曜。
      expect(homeWidgetGridStart(DateTime(2026, 11, 1)), DateTime(2026, 11, 1));
    });

    test('今日から1週間先までは必ず範囲に入る（リスト側ウィジェットの前提）', () {
      // 月末（グリッド範囲の下限が効きにくい日）でも成り立つこと。
      for (final day in [
        DateTime(2026, 7, 31, 23),
        DateTime(2026, 12, 31, 23),
        DateTime(2026, 2, 28),
      ]) {
        final range = homeWidgetDayRange(day);
        expect(range.start.isAfter(day), isFalse, reason: '$day');
        expect(
          range.end.isAfter(DateTime(day.year, day.month, day.day + 7)),
          isTrue,
          reason: '$day',
        );
      }
    });
  });

  group('buildHomeWidgetPayload', () {
    test('グリッド範囲の各日を、日付昇順で 1 つずつ作る', () {
      final payload = build(events: const []);

      final dates = datesOf(payload);
      expect(dates.first, '2026-06-28');
      expect(dates.last, '2026-09-05');
      expect(dates.length, dates.toSet().length, reason: '日付の重複なし');
      expect(dates, contains(today));
      expect(dates, contains(tomorrow));
      expect(payload['version'], homeWidgetPayloadVersion);
      expect(payload['signedIn'], isTrue);
    });

    test('FR-4: 祝日は名称を載せ、祝日でない日はキーごと省く', () {
      final payload = build(events: const []);

      // 2026-07-20 は海の日。
      expect(_day(payload, '2026-07-20')['holiday'], '海の日');
      expect(_day(payload, today).containsKey('holiday'), isFalse);
    });

    test('件数はマスの「+N」用に total で渡す（載せる件数とは別）', () {
      final payload = build(
        events: [
          for (
            var index = 0;
            index < homeWidgetMaxEntriesPerDay + 3;
            index += 1
          )
            _event(
              id: 'event-$index',
              start: DateTime(2026, 7, 28, 8).add(Duration(minutes: index)),
            ),
        ],
      );

      expect(_day(payload, today)['total'], homeWidgetMaxEntriesPerDay + 3);
      expect(_entries(payload, today).length, homeWidgetMaxEntriesPerDay);
      expect(_day(payload, tomorrow)['total'], 0);
    });

    test('Issue #112: まとめ帯の地色は、設定されているときだけ載せる', () {
      expect(
        build(events: const [], mergedBarColor: '#F1E2BD')['mergedBarColor'],
        '#F1E2BD',
      );
      expect(build(events: const []).containsKey('mergedBarColor'), isFalse);
    });

    test('予定はその日の枠にだけ入る', () {
      final payload = build(
        events: [
          _event(id: 'today', start: DateTime(2026, 7, 28, 10)),
          _event(id: 'tomorrow', start: DateTime(2026, 7, 29, 10)),
        ],
      );

      expect(_entries(payload, today).single['time'], '10:00');
      expect(_entries(payload, tomorrow).single['time'], '10:00');
    });

    test('日をまたぐ予定は、またいだ各日に出る', () {
      final payload = build(
        events: [
          _event(
            id: 'trip',
            title: '旅行',
            start: DateTime(2026, 7, 28),
            end: DateTime(2026, 7, 30),
            allDay: true,
          ),
        ],
      );

      for (final date in [today, tomorrow, '2026-07-30']) {
        expect(_entries(payload, date).single['title'], '旅行', reason: date);
      }
      expect(_entries(payload, '2026-07-31'), isEmpty);
    });

    test('今日より前に始まり今日で終わる予定も、今日の枠に出る', () {
      final payload = build(
        events: [
          _event(
            id: 'overnight',
            start: DateTime(2026, 7, 27, 22),
            end: DateTime(2026, 7, 28, 1),
          ),
        ],
      );

      expect(_entries(payload, today).single['time'], '〜01:00');
    });

    test('時刻表記は「その日にとって何時か」で決まる', () {
      final startsToday = _event(id: 'a', start: DateTime(2026, 7, 28, 9, 5));
      final allDay = _event(
        id: 'b',
        start: DateTime(2026, 7, 28),
        allDay: true,
      );
      // 27日22時〜29日6時。28日は丸一日ふさがるため「終日」。
      final spansWholeDay = _event(
        id: 'c',
        start: DateTime(2026, 7, 27, 22),
        end: DateTime(2026, 7, 29, 6),
      );

      expect(homeWidgetTimeLabel(startsToday, DateTime(2026, 7, 28)), '09:05');
      expect(homeWidgetTimeLabel(allDay, DateTime(2026, 7, 28)), '終日');
      expect(homeWidgetTimeLabel(spansWholeDay, DateTime(2026, 7, 28)), '終日');
    });

    test('FR-2: 参加者の識別色をドットぶんだけ載せ、引けない参加者はグレーにする', () {
      final payload = build(
        events: [
          _event(
            id: 'family',
            start: DateTime(2026, 7, 28, 10),
            participants: const ['mom', 'dad', 'kid', 'gone', 'extra'],
          ),
        ],
        membersById: {
          'mom': _user('mom', '#B7412E'),
          'dad': _user('dad', '#2B5A7E'),
          'kid': _user('kid', '#3F6B3A'),
          'extra': _user('extra', '#D9A62E'),
        },
      );

      expect(_entries(payload, today).single['colors'], [
        '#B7412E',
        '#2B5A7E',
        '#3F6B3A',
      ]);

      final withDeactivated = build(
        events: [
          _event(
            id: 'solo',
            start: DateTime(2026, 7, 28, 10),
            participants: const ['gone'],
          ),
        ],
      );
      expect(_entries(withDeactivated, today).single['colors'], [
        homeWidgetFallbackColor,
      ]);
    });

    test('FR-3: 仮の予定は tentative で区別できる', () {
      final payload = build(
        events: [
          _event(
            id: 'maybe',
            start: DateTime(2026, 7, 28, 10),
            type: EventType.tentative,
          ),
          _event(id: 'fixed', start: DateTime(2026, 7, 28, 11)),
        ],
      );

      expect(_entries(payload, today).map((entry) => entry['tentative']), [
        true,
        false,
      ]);
    });

    test('並びは日別一覧と同じ（自分の予定→優先度→終日→開始時刻）', () {
      final payload = build(
        events: [
          _event(id: 'other', start: DateTime(2026, 7, 28, 8), title: '他の人'),
          _event(
            id: 'important',
            start: DateTime(2026, 7, 28, 20),
            title: '重要',
            priority: highestEventPriority,
          ),
          _event(
            id: 'mine',
            start: DateTime(2026, 7, 28, 23),
            title: '自分',
            participants: const ['me'],
          ),
        ],
        currentUid: 'me',
      );

      expect(_entries(payload, today).map((entry) => entry['title']), [
        '自分',
        '重要',
        '他の人',
      ]);
    });

    test('1 日あたりの件数は homeWidgetMaxEntriesPerDay で打ち切る', () {
      final payload = build(
        events: [
          for (
            var index = 0;
            index < homeWidgetMaxEntriesPerDay + 5;
            index += 1
          )
            _event(
              id: 'event-$index',
              start: DateTime(2026, 7, 28, 8).add(Duration(minutes: index)),
            ),
        ],
      );

      expect(_entries(payload, today).length, homeWidgetMaxEntriesPerDay);
    });
  });

  group('buildSignedOutHomeWidgetPayload', () {
    test('サインアウト時は予定を載せない（NFR-4）', () {
      final payload = buildSignedOutHomeWidgetPayload();

      expect(payload['signedIn'], isFalse);
      expect(payload['days'], isEmpty);
      expect(payload['version'], homeWidgetPayloadVersion);
    });
  });

  group('encodeHomeWidgetPayload', () {
    test('Android 側が読む JSON へ変換できる', () {
      final json = encodeHomeWidgetPayload(
        build(
          events: [
            _event(id: 'a', start: DateTime(2026, 7, 28, 10), title: '打ち合わせ'),
          ],
        ),
      );

      final decoded = jsonDecode(json) as Map<String, Object?>;
      expect(decoded['version'], homeWidgetPayloadVersion);
      expect(_entries(decoded, today).single['title'], '打ち合わせ');
    });

    test('内容が同じなら同じ文字列になる（不要な書き込みを避けられる）', () {
      List<Event> events() => [
        _event(id: 'a', start: DateTime(2026, 7, 28, 10)),
      ];

      expect(
        encodeHomeWidgetPayload(build(events: events())),
        encodeHomeWidgetPayload(build(events: events())),
      );
    });
  });
}
