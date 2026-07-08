import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreData = Map<String, Object?>;

DateTime dateTimeFromFirestore(
  Object? value,
  String fieldName, {
  DateTime? pendingWriteEstimate,
}) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
  }
  // serverTimestamp() で書いたフィールドは、サーバー確定前のローカル反映
  // （pending write）の間だけ null で届く。呼び出し側が推定値を渡していれば
  // それを採用し、無ければ未確定データとしてエラーにする。
  if (value == null && pendingWriteEstimate != null) {
    return pendingWriteEstimate;
  }
  throw FormatException('$fieldName must be a Firestore Timestamp.');
}

Object updatedAtForFirestore(
  DateTime updatedAt, {
  required bool useServerTimestamp,
}) {
  return useServerTimestamp
      ? FieldValue.serverTimestamp()
      : Timestamp.fromDate(updatedAt);
}
