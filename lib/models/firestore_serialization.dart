import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreData = Map<String, Object?>;

DateTime dateTimeFromFirestore(Object? value, String fieldName) {
  if (value is Timestamp) {
    return value.toDate().toUtc();
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
