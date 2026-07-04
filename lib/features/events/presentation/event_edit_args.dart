import '../../../models/models.dart';

/// 予定編集画面（#11）への遷移引数。
///
/// - [EventEditArgs.create]: 指定日を初期値に新規作成する。
/// - [EventEditArgs.edit]: 既存予定を編集する。
class EventEditArgs {
  const EventEditArgs.create(DateTime this.initialDate) : event = null;

  const EventEditArgs.edit(Event this.event) : initialDate = null;

  /// 編集対象の既存予定。新規作成時は null。
  final Event? event;

  /// 新規作成時の初期日付。編集時は null。
  final DateTime? initialDate;

  bool get isCreate => event == null;
}
