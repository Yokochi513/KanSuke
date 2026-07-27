/// 月表示の帯を週内のレーン（縦位置）へ割り当てる（Issue #72 / #76 / #177）。
///
/// 週は日曜〜土曜の 7 列。1 本の帯は連続した列範囲を占め、列が重ならない帯同士は
/// 同じレーンを使い回す。マスに収まらないレーンは呼び出し側で「+N」に集約する。
library;

/// 週内 1 本ぶんのレーン割り当て入力（Issue #177）。
class WeekLaneItem {
  WeekLaneItem({
    required this.startCol,
    required this.endCol,
    required this.isMine,
  }) : assert(startCol >= 0 && startCol < columnsPerWeek),
       assert(endCol >= startCol && endCol < columnsPerWeek);

  /// その週での開始列（0＝日曜〜6＝土曜）。
  final int startCol;

  /// その週での終了列（0＝日曜〜6＝土曜、両端を含む）。
  final int endCol;

  /// 自分が参加している予定かどうか（FR-1 / FR-2）。
  final bool isMine;
}

/// 週の列数（日曜〜土曜）。
const int columnsPerWeek = 7;

/// 週内のレーンを割り当て、[items] と同じ並びでレーン番号（0 起点）を返す。
///
/// FR-1 / FR-2 / Issue #177: **自分が参加する予定を先に配置する**。夏休みのような
/// 長期予定は週頭から始まるため、開始日順にだけ詰めると常に上のレーンを取り、自分の
/// 予定が押し下げられてマスの「+N」に隠れてしまうため。
///
/// 同順位（どちらも自分の予定／どちらも他の予定）は開始列の早い順、さらに同着なら
/// **[items] の並び順**を保つ。呼び出し側が表示優先度順に渡す前提で、結果として
/// 「自分の予定 → 開始列 → 表示優先度」の順にレーンが埋まる。
///
/// 自分の予定を先に置く都合上、処理順は開始列順にならない。そのためレーンの空きは
/// 「最後に置いた帯の終了列」ではなく **レーンごとの列占有** で判定する。終了列を 1 つ
/// 覚えるだけの貪欲彩色だと、先に置いた帯より前の列が空いていても再利用できず、
/// レーン総数が無駄に増えて「+N」がかえって増えてしまう。
///
/// この列占有方式は、自分の予定が 1 件も無い（＝入力順＝開始列順で処理される）場合に
/// 従来の貪欲彩色と同じ結果になる。
List<int> assignWeekLanes(List<WeekLaneItem> items) {
  final order = [for (var i = 0; i < items.length; i++) i]
    ..sort((a, b) {
      final first = items[a];
      final second = items[b];
      if (first.isMine != second.isMine) {
        return first.isMine ? -1 : 1;
      }
      final byStart = first.startCol.compareTo(second.startCol);
      if (byStart != 0) return byStart;
      // List.sort は安定ソートではないため、入力順を保つには添字での比較が要る。
      return a.compareTo(b);
    });

  final occupied = <List<bool>>[];
  final lanes = List<int>.filled(items.length, 0);
  for (final index in order) {
    final item = items[index];
    var lane = 0;
    while (true) {
      if (lane == occupied.length) {
        occupied.add(List<bool>.filled(columnsPerWeek, false));
      }
      if (_isFree(occupied[lane], item.startCol, item.endCol)) break;
      lane++;
    }
    for (var col = item.startCol; col <= item.endCol; col++) {
      occupied[lane][col] = true;
    }
    lanes[index] = lane;
  }
  return lanes;
}

/// [lane] の [startCol]〜[endCol]（両端を含む）が空いているか。
bool _isFree(List<bool> lane, int startCol, int endCol) {
  for (var col = startCol; col <= endCol; col++) {
    if (lane[col]) return false;
  }
  return true;
}
