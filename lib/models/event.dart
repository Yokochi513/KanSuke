import 'dart:collection';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import 'firestore_serialization.dart';

enum EventType {
  tentative,
  confirmed;

  static EventType fromFirestore(String value) {
    return EventType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => throw FormatException('Unknown event type: $value'),
    );
  }
}

enum EventRecurrenceFrequency {
  weekly,
  monthly,
  yearly;

  static EventRecurrenceFrequency? fromFirestore(String? value) {
    if (value == null) return null;
    return EventRecurrenceFrequency.values.firstWhere(
      (frequency) => frequency.name == value,
      orElse: () =>
          throw FormatException('Unknown recurrence frequency: $value'),
    );
  }
}

const _unset = Object();

/// 予定データ。FR-1〜FR-3 / FR-5 の永続化単位。
final class Event {
  Event({
    required this.id,
    required this.title,
    required this.creatorId,
    required List<String> participantIds,
    required this.startAt,
    required this.endAt,
    required this.allDay,
    required this.type,
    required this.memo,
    required Map<String, List<int>> reminderOffsets,
    required this.updatedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    required this.calendarId,
    this.recurrenceFrequency,
    this.recurrenceCount,
    List<DateTime> recurrenceExceptions = const [],
    this.recurrenceUntil,
    this.recurrenceMasterStartAt,
    this.recurrenceMasterEndAt,
  }) : participantIds = UnmodifiableListView(participantIds),
       recurrenceExceptions = UnmodifiableListView(recurrenceExceptions),
       reminderOffsets = UnmodifiableMapView({
         for (final entry in reminderOffsets.entries)
           entry.key: UnmodifiableListView(entry.value),
       });

  factory Event.create({
    required String title,
    required String creatorId,
    List<String> participantIds = const [],
    required DateTime startAt,
    required DateTime endAt,
    required bool allDay,
    required EventType type,
    required String memo,
    required Map<String, List<int>> reminderOffsets,
    required String updatedBy,
    required DateTime now,
    required String calendarId,
    EventRecurrenceFrequency? recurrenceFrequency,
    int? recurrenceCount,
    Uuid uuid = const Uuid(),
  }) {
    return Event(
      id: uuid.v4(),
      title: title,
      creatorId: creatorId,
      participantIds: participantIds,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      type: type,
      memo: memo,
      reminderOffsets: reminderOffsets,
      updatedBy: updatedBy,
      createdAt: now,
      updatedAt: now,
      deleted: false,
      calendarId: calendarId,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
    );
  }

  factory Event.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw StateError('Event document ${snapshot.id} does not exist.');
    }
    return Event.fromMap(snapshot.id, data);
  }

  factory Event.fromMap(String id, FirestoreData data) {
    return Event(
      id: id,
      title: data['title'] as String,
      // 所有者(ownerId)から作成者(creatorId)へのフィールド改名前のドキュメントを
      // 読めるよう、旧キーへフォールバックする。
      creatorId: (data['creatorId'] ?? data['ownerId']) as String,
      // 参加者機能導入前のドキュメントにはキーが存在しないため空リストにフォールバックする。
      participantIds: (data['participantIds'] as List<Object?>? ?? const [])
          .map((id) => id as String)
          .toList(),
      startAt: dateTimeFromFirestore(data['startAt'], 'startAt'),
      endAt: dateTimeFromFirestore(data['endAt'], 'endAt'),
      allDay: data['allDay'] as bool,
      type: EventType.fromFirestore(data['type'] as String),
      memo: data['memo'] as String,
      // FR-5: リマインドは各自が自分の分だけ設定する（uid → 分の map、Issue #14）。
      // 旧形式（予定で共有する number[]）とキー欠落は「設定なし」として読む。
      reminderOffsets: _reminderOffsetsFromFirestore(data['reminderOffsets']),
      updatedBy: data['updatedBy'] as String,
      createdAt: dateTimeFromFirestore(data['createdAt'], 'createdAt'),
      // updatedAt は serverTimestamp() 書き込みのため、サーバー確定前は
      // ローカルの現在時刻を暫定値として扱う（確定後のスナップショットで
      // 正しい値に更新される）。
      updatedAt: dateTimeFromFirestore(
        data['updatedAt'],
        'updatedAt',
        pendingWriteEstimate: DateTime.now().toUtc(),
      ),
      deleted: data['deleted'] as bool,
      // FR-8: calendarId は必須（Issue #93）。旧・既定カレンダー（'default'）への
      // フォールバックは、移行スクリプトで全予定に calendarId が実在するように
      // なったため廃止した。
      calendarId: data['calendarId'] as String,
      recurrenceFrequency: EventRecurrenceFrequency.fromFirestore(
        data['recurrenceFrequency'] as String?,
      ),
      // Firestore の number は int 以外の num 実装で届く可能性があるため、
      // nil と型変換の境界をここで閉じる。
      recurrenceCount: (data['recurrenceCount'] as num?)?.toInt(),
      // #86: 繰り返しの例外日（EXDATE 相当）と打ち切り日。導入前の
      // ドキュメントにはキーが無いため、それぞれ空リスト・null にフォールバックする。
      recurrenceExceptions: _recurrenceExceptionsFromFirestore(
        data['recurrenceExceptions'],
      ),
      recurrenceUntil: data['recurrenceUntil'] == null
          ? null
          : dateTimeFromFirestore(data['recurrenceUntil'], 'recurrenceUntil'),
    );
  }

  final String id;
  final String title;
  final String creatorId;
  final List<String> participantIds;
  final DateTime startAt;
  final DateTime endAt;
  final bool allDay;
  final EventType type;
  final String memo;

  /// リマインドの「開始 n 分前」（FR-5、Issue #14）。
  ///
  /// キーは設定した本人の uid。通知はその本人にだけ届くため、他のメンバーの
  /// 設定を代わりに変えることはしない（編集時もそのまま引き継ぐ）。
  final Map<String, List<int>> reminderOffsets;
  final String updatedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String calendarId;
  final EventRecurrenceFrequency? recurrenceFrequency;
  final int? recurrenceCount;

  /// 繰り返しの例外日（EXDATE 相当、#86）。
  ///
  /// 「この予定のみ削除」で除外した各発生日の開始日時（UTC）を持つ。月表示の
  /// 展開時に、この一覧に一致する発生日は生成しない。オフラインでの並行削除を
  /// 素直にマージできるよう、書き込みは `arrayUnion` で追記する。
  final List<DateTime> recurrenceExceptions;

  /// 繰り返しの打ち切り日（#86）。この日時**以降**の発生日は生成しない（排他境界）。
  ///
  /// 「これ以降の予定を削除」で、削除した発生日の開始日時を設定する。null なら
  /// 打ち切りなし。`recurrenceCount` とは独立に働き、両方あれば早い方で止まる。
  final DateTime? recurrenceUntil;

  /// 表示用に展開した繰り返し予定が、編集時に元の開始/終了へ戻るための値。
  ///
  /// Firestore には保存しない一時フィールド。null なら元ドキュメントそのもの。
  final DateTime? recurrenceMasterStartAt;
  final DateTime? recurrenceMasterEndAt;

  bool get isRecurring => recurrenceFrequency != null;

  bool get isRecurrenceOccurrence =>
      recurrenceMasterStartAt != null && recurrenceMasterEndAt != null;

  /// 色分け表示（月表示の分割バー・日別一覧の複数ドット）で使う表示順の ID 一覧。
  ///
  /// 参加者を重複なく並べたもの。参加者機能導入前の未移行ドキュメント等、
  /// 参加者が空の場合のみ作成者にフォールバックする（表示が空にならないように）。
  List<String> get memberIds {
    if (participantIds.isEmpty) return [creatorId];
    final seen = <String>{};
    return [
      for (final id in participantIds)
        if (seen.add(id)) id,
    ];
  }

  FirestoreData toFirestore({bool useServerTimestamp = true}) {
    final startAtForFirestore = recurrenceMasterStartAt ?? startAt;
    final endAtForFirestore = recurrenceMasterEndAt ?? endAt;
    return {
      'id': id,
      'title': title,
      'creatorId': creatorId,
      'participantIds': participantIds.toList(),
      'startAt': Timestamp.fromDate(startAtForFirestore),
      'endAt': Timestamp.fromDate(endAtForFirestore),
      'allDay': allDay,
      'type': type.name,
      'memo': memo,
      'reminderOffsets': {
        for (final entry in reminderOffsets.entries)
          entry.key: entry.value.toList(),
      },
      'updatedBy': updatedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAtForFirestore(
        updatedAt,
        useServerTimestamp: useServerTimestamp,
      ),
      'deleted': deleted,
      'calendarId': calendarId,
      'recurrenceFrequency': recurrenceFrequency?.name,
      'recurrenceCount': recurrenceCount,
      // #86: 例外日・打ち切り日は繰り返しの元ドキュメント側に持つ。
      'recurrenceExceptions': [
        for (final exception in recurrenceExceptions)
          Timestamp.fromDate(exception),
      ],
      'recurrenceUntil': recurrenceUntil == null
          ? null
          : Timestamp.fromDate(recurrenceUntil!),
    };
  }

  /// 編集で実際に変更したフィールドだけを含む差分更新マップ（Issue #114）。
  ///
  /// 基本設計 §4.2 は競合解決を**フィールド単位の Last-Write-Wins** と定める。
  /// ところが全フィールドを書く `toFirestore()` を `update()` に渡すと、実質は
  /// **ドキュメント単位**の LWW になり、2 端末がオフラインで別々のフィールドを
  /// 編集して同期した際に、後着の保存が相手の変更まで丸ごと上書きしてしまう
  /// （lost update）。そこで [previous]（編集前の値）と比較し、変わった
  /// フィールドだけを書き込むことでフィールド単位の LWW を実現する。
  ///
  /// - `updatedBy` / `updatedAt` は常に更新する（誰がいつ触ったかの監査）。
  /// - `id` / `creatorId` / `createdAt` は不変なので載らない（比較上も一致）。
  /// - `deleted` / `recurrenceExceptions` / `recurrenceUntil` は削除系の専用
  ///   操作（softDelete / excludeOccurrence / truncateRecurrenceFrom）が
  ///   `arrayUnion` 等で個別に管理するため、編集保存では触れない。他端末の
  ///   並行削除を編集保存が巻き戻さないようにする狙いでもある。
  FirestoreData toFirestoreUpdate(
    Event previous, {
    bool useServerTimestamp = true,
  }) {
    final startAtValue = recurrenceMasterStartAt ?? startAt;
    final endAtValue = recurrenceMasterEndAt ?? endAt;
    final prevStartAt = previous.recurrenceMasterStartAt ?? previous.startAt;
    final prevEndAt = previous.recurrenceMasterEndAt ?? previous.endAt;

    final data = <String, Object?>{};
    if (title != previous.title) data['title'] = title;
    if (!_participantIdsEqual(participantIds, previous.participantIds)) {
      data['participantIds'] = participantIds.toList();
    }
    if (startAtValue != prevStartAt) {
      data['startAt'] = Timestamp.fromDate(startAtValue);
    }
    if (endAtValue != prevEndAt) {
      data['endAt'] = Timestamp.fromDate(endAtValue);
    }
    if (allDay != previous.allDay) data['allDay'] = allDay;
    if (type != previous.type) data['type'] = type.name;
    if (memo != previous.memo) data['memo'] = memo;
    if (!_reminderOffsetsEqual(reminderOffsets, previous.reminderOffsets)) {
      data['reminderOffsets'] = {
        for (final entry in reminderOffsets.entries)
          entry.key: entry.value.toList(),
      };
    }
    if (calendarId != previous.calendarId) data['calendarId'] = calendarId;
    if (recurrenceFrequency != previous.recurrenceFrequency) {
      data['recurrenceFrequency'] = recurrenceFrequency?.name;
    }
    if (recurrenceCount != previous.recurrenceCount) {
      data['recurrenceCount'] = recurrenceCount;
    }

    data['updatedBy'] = updatedBy;
    data['updatedAt'] = updatedAtForFirestore(
      updatedAt,
      useServerTimestamp: useServerTimestamp,
    );
    return data;
  }

  Event occurrenceAt({required DateTime startAt, required DateTime endAt}) {
    return Event(
      id: id,
      title: title,
      creatorId: creatorId,
      participantIds: participantIds,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      type: type,
      memo: memo,
      reminderOffsets: reminderOffsets,
      updatedBy: updatedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: deleted,
      calendarId: calendarId,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
      recurrenceExceptions: recurrenceExceptions.toList(),
      recurrenceUntil: recurrenceUntil,
      recurrenceMasterStartAt: this.startAt,
      recurrenceMasterEndAt: this.endAt,
    );
  }

  Event get masterEventForEditing {
    if (!isRecurrenceOccurrence) return this;
    return Event(
      id: id,
      title: title,
      creatorId: creatorId,
      participantIds: participantIds,
      startAt: recurrenceMasterStartAt!,
      endAt: recurrenceMasterEndAt!,
      allDay: allDay,
      type: type,
      memo: memo,
      reminderOffsets: reminderOffsets,
      updatedBy: updatedBy,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deleted: deleted,
      calendarId: calendarId,
      recurrenceFrequency: recurrenceFrequency,
      recurrenceCount: recurrenceCount,
      recurrenceExceptions: recurrenceExceptions.toList(),
      recurrenceUntil: recurrenceUntil,
    );
  }

  Event copyWith({
    String? id,
    String? title,
    String? creatorId,
    List<String>? participantIds,
    DateTime? startAt,
    DateTime? endAt,
    bool? allDay,
    EventType? type,
    String? memo,
    Map<String, List<int>>? reminderOffsets,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
    String? calendarId,
    Object? recurrenceFrequency = _unset,
    Object? recurrenceCount = _unset,
    List<DateTime>? recurrenceExceptions,
    Object? recurrenceUntil = _unset,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      creatorId: creatorId ?? this.creatorId,
      participantIds: participantIds ?? this.participantIds,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      allDay: allDay ?? this.allDay,
      type: type ?? this.type,
      memo: memo ?? this.memo,
      reminderOffsets: reminderOffsets ?? this.reminderOffsets,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      calendarId: calendarId ?? this.calendarId,
      recurrenceFrequency: identical(recurrenceFrequency, _unset)
          ? this.recurrenceFrequency
          : recurrenceFrequency as EventRecurrenceFrequency?,
      recurrenceCount: identical(recurrenceCount, _unset)
          ? this.recurrenceCount
          : recurrenceCount as int?,
      recurrenceExceptions:
          recurrenceExceptions ?? this.recurrenceExceptions.toList(),
      recurrenceUntil: identical(recurrenceUntil, _unset)
          ? this.recurrenceUntil
          : recurrenceUntil as DateTime?,
      recurrenceMasterStartAt: recurrenceMasterStartAt,
      recurrenceMasterEndAt: recurrenceMasterEndAt,
    );
  }

  /// [uid] が自分に設定しているリマインド（開始 n 分前）。
  List<int> reminderOffsetsFor(String uid) =>
      reminderOffsets[uid] ?? const <int>[];
}

/// Firestore の `reminderOffsets` を `{uid: [分, ...]}` として読む（Issue #14）。
///
/// 旧形式（予定で共有する `number[]`）とキー欠落は「設定なし」として扱う
/// （旧データは移行せず破棄）。Firestore の number は int 以外の num 実装で
/// 届く可能性があるため、型変換の境界をここで閉じる。
Map<String, List<int>> _reminderOffsetsFromFirestore(Object? value) {
  if (value is! Map) return const {};
  final offsetsByUid = <String, List<int>>{};
  for (final entry in value.entries) {
    final uid = entry.key;
    final offsets = entry.value;
    if (uid is! String || offsets is! List) continue;
    offsetsByUid[uid] = offsets
        .whereType<num>()
        .map((offset) => offset.toInt())
        .toList();
  }
  return offsetsByUid;
}

/// 参加者集合が同じかを順不同で比較する（Issue #114 の差分更新用）。
///
/// 参加者は追加/削除でしか変えられず、保存時は常にソートして書くため、順序の
/// 違いは意味を持たない。集合として一致すれば「変更なし」とみなし、無用な
/// 上書き（他端末の参加者変更を巻き戻す危険）を避ける。
bool _participantIdsEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  return a.toSet().containsAll(b) && b.toSet().containsAll(a);
}

/// リマインド設定（uid → 分の一覧）が同じかを、各 uid の分集合を順不同で比較する
/// （Issue #114 の差分更新用）。分は集合として扱い保存時はソートするため、順序の
/// 違いは変更とみなさない。
bool _reminderOffsetsEqual(Map<String, List<int>> a, Map<String, List<int>> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null) return false;
    if (entry.value.length != other.length) return false;
    if (!entry.value.toSet().containsAll(other)) return false;
  }
  return true;
}

/// Firestore の `recurrenceExceptions`（Timestamp の配列）を UTC の [DateTime]
/// 一覧として読む（#86）。キー欠落・非配列・Timestamp 以外の要素は無視する。
List<DateTime> _recurrenceExceptionsFromFirestore(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Timestamp) item.toDate().toUtc(),
  ];
}
