import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/logger.dart';
import '../../../models/models.dart';

const _logTag = 'EventRepository';

/// events コレクションへの CRUD とリアルタイム取得を担う。
///
/// FR-1（予定の登録・閲覧）/ FR-6（同期）/ 基本設計 §3.2・§4。
/// - ドキュメント ID はクライアント生成 UUID（[Event.create]）。
/// - `updatedBy` は書き込み時に呼び出し側（本人 uid）から受け取る。
///   認証状態に依存しない購読グラフにして、サインアウト時のテアダウン中に
///   購読が dirty 化して再描画がビルド中に走るのを避ける。
/// - `updatedAt` は `serverTimestamp()` を付与する。
/// - 削除はソフト削除（`deleted=true`）として LWW で伝播させる（§4.2）。
class EventRepository {
  EventRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('events');

  /// 予定を作成する（ドキュメント ID は [event] の UUID）。
  ///
  /// `updatedBy` を [updatedBy] に上書きし、`updatedAt` は serverTimestamp とする。
  Future<void> create(Event event, {required String updatedBy}) {
    final data = event.copyWith(updatedBy: updatedBy).toFirestore();
    return _events.doc(event.id).set(data).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      AppLogger.error(
        'Failed to create event ${event.id}',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw error;
    });
  }

  /// 既存予定を更新する。`updatedBy`/`updatedAt` を更新する。
  Future<void> update(Event event, {required String updatedBy}) {
    final data = event.copyWith(updatedBy: updatedBy).toFirestore();
    // FR-1: 作成者は予定を作った人の固定情報なので、編集保存では上書きしない。
    data.remove('creatorId');
    return _events.doc(event.id).update(data).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      AppLogger.error(
        'Failed to update event ${event.id}',
        tag: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      throw error;
    });
  }

  /// 仮↔確定の切替（FR-3）。`type` 更新のみで完結させる。
  Future<void> setType(
    String eventId,
    EventType type, {
    required String updatedBy,
  }) {
    return _events
        .doc(eventId)
        .update({
          'type': type.name,
          'updatedBy': updatedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to set type for event $eventId',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }

  /// ソフト削除（§4.2）。物理削除はサーバ側の定期パージに委ねる。
  Future<void> softDelete(String eventId, {required String updatedBy}) {
    return _events
        .doc(eventId)
        .update({
          'deleted': true,
          'updatedBy': updatedBy,
          'updatedAt': FieldValue.serverTimestamp(),
        })
        .catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Failed to soft-delete event $eventId',
            tag: _logTag,
            error: error,
            stackTrace: stackTrace,
          );
          throw error;
        });
  }

  /// 期間 `[start, end)` かつ指定カレンダーの予定をリアルタイムに監視する
  /// （FR-4 の月表示に利用、FR-8 のカレンダー切替に対応）。
  ///
  /// `deleted==false`・`calendarId` 一致・`[startAt, endAt]` が指定期間と
  /// 重なる予定を取得し `startAt` 昇順で返す。
  /// 複合インデックス（deleted ASC, calendarId ASC, startAt ASC）を前提とする。
  ///
  /// `calendarId` は実際の `where` 句として絞り込む（クライアント側フィルタでは
  /// 不十分）。Firestore Security Rules は複数件取得クエリに対し、クエリの
  /// `where` 句だけでルール適合を静的に証明できない場合はクエリ全体を拒否する。
  /// `calendarId` を絞り込まずに取得すると、他カレンダーの予定が1件でも
  /// 期間内にあった時点でルールがクエリ全体を拒否してしまう（FR-8）。
  ///
  /// Issue #60: 繰り返し予定は元の `startAt` が表示月より前でも将来月に
  /// 出現するため、`endAt >= start` は Firestore の where 句に入れず、
  /// 取得後に表示範囲内の発生日だけへ展開する。家庭内少人数運用前提の
  /// シンプルな実装で、将来ユーザー数や件数が増える場合は専用インデックスや
  /// 派生 occurrence コレクションを検討する。
  /// Firestore の既定でローカルキャッシュ起点に描画される（NFR-1）。
  Stream<List<Event>> watchRange({
    required DateTime start,
    required DateTime end,
    required String calendarId,
  }) {
    // 既存の終日単日予定は startAt == endAt のため、終了境界は含める。
    return _events
        .where('deleted', isEqualTo: false)
        .where('calendarId', isEqualTo: calendarId)
        .where('startAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('startAt')
        .snapshots()
        .map((snapshot) {
          final events = <Event>[];
          for (final doc in snapshot.docs) {
            try {
              events.addAll(
                _expandForRange(
                  Event.fromFirestore(doc),
                  start: start,
                  end: end,
                ),
              );
            } catch (error, stackTrace) {
              // 1件のドキュメントの変換失敗（未移行フィールドの欠落・不正な
              // 型など）で月表示全体がエラーにならないよう、当該ドキュメント
              // だけ除外してログに残す。障害調査は AppLogger の出力を見る。
              AppLogger.error(
                'Failed to parse event ${doc.id}, skipping it',
                tag: _logTag,
                error: error,
                stackTrace: stackTrace,
              );
            }
          }
          events.sort(_compareBySchedule);
          return events;
        });
  }

  Iterable<Event> _expandForRange(
    Event event, {
    required DateTime start,
    required DateTime end,
  }) sync* {
    final frequency = event.recurrenceFrequency;
    if (frequency == null) {
      if (_overlaps(event.startAt, event.endAt, start, end)) {
        yield event;
      }
      return;
    }

    final recurrenceCount = event.recurrenceCount;
    for (
      var occurrenceIndex = 0;
      recurrenceCount == null || occurrenceIndex < recurrenceCount;
      occurrenceIndex += 1
    ) {
      final occurrenceStart = _addRecurrenceOffset(
        event.startAt,
        frequency,
        occurrenceIndex,
      );
      final occurrenceEnd = _addRecurrenceOffset(
        event.endAt,
        frequency,
        occurrenceIndex,
      );

      if (!occurrenceStart.isBefore(end)) {
        break;
      }
      if (_overlaps(occurrenceStart, occurrenceEnd, start, end)) {
        yield event.occurrenceAt(
          startAt: occurrenceStart,
          endAt: occurrenceEnd,
        );
      }
    }
  }

  bool _overlaps(
    DateTime eventStart,
    DateTime eventEnd,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    return eventStart.isBefore(rangeEnd) && !eventEnd.isBefore(rangeStart);
  }

  DateTime _addRecurrenceOffset(
    DateTime dateTime,
    EventRecurrenceFrequency frequency,
    int occurrenceIndex,
  ) {
    return switch (frequency) {
      EventRecurrenceFrequency.weekly => dateTime.add(
        Duration(days: DateTime.daysPerWeek * occurrenceIndex),
      ),
      EventRecurrenceFrequency.monthly => _addMonthsClamped(
        dateTime,
        occurrenceIndex,
      ),
      EventRecurrenceFrequency.yearly => _addMonthsClamped(
        dateTime,
        occurrenceIndex * DateTime.monthsPerYear,
      ),
    };
  }

  DateTime _addMonthsClamped(DateTime dateTime, int months) {
    final monthIndex = dateTime.month - 1 + months;
    final targetYear = dateTime.year + monthIndex ~/ DateTime.monthsPerYear;
    final targetMonth = monthIndex % DateTime.monthsPerYear + 1;
    final targetDay = _clampDayToMonth(
      year: targetYear,
      month: targetMonth,
      day: dateTime.day,
    );
    if (dateTime.isUtc) {
      return DateTime.utc(
        targetYear,
        targetMonth,
        targetDay,
        dateTime.hour,
        dateTime.minute,
        dateTime.second,
        dateTime.millisecond,
        dateTime.microsecond,
      );
    }
    return DateTime(
      targetYear,
      targetMonth,
      targetDay,
      dateTime.hour,
      dateTime.minute,
      dateTime.second,
      dateTime.millisecond,
      dateTime.microsecond,
    );
  }

  int _clampDayToMonth({
    required int year,
    required int month,
    required int day,
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day > lastDay ? lastDay : day;
  }

  int _compareBySchedule(Event first, Event second) {
    final byStart = first.startAt.compareTo(second.startAt);
    if (byStart != 0) return byStart;
    final byEnd = first.endAt.compareTo(second.endAt);
    if (byEnd != 0) return byEnd;
    return first.id.compareTo(second.id);
  }
}
