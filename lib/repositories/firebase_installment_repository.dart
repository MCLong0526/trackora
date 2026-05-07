import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/installment.dart';
import 'installment_repository.dart';

class FirebaseInstallmentRepository implements InstallmentRepository {
  final FirebaseFirestore _db;

  FirebaseInstallmentRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String userId) {
    return _db.collection('users').doc(userId).collection('installments');
  }

  @override
  Stream<List<Installment>> getAll(String userId) {
    return _ref(userId)
        .orderBy('dayOfMonth')
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).toList());
  }

  @override
  Future<void> add(String userId, Installment installment) async {
    await _ref(userId).add(_toFirestoreMap(installment));
  }

  @override
  Future<void> update(String userId, Installment installment) async {
    await _ref(userId).doc(installment.id).update(_toFirestoreMap(installment));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _ref(userId).doc(id).delete();
  }

  Future<void> upsert(String userId, Installment installment) async {
    await _ref(userId)
        .doc(installment.id)
        .set(_toFirestoreMap(installment), SetOptions(merge: true));
  }

  Installment _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Installment document ${doc.id} is empty.');
    }
    return Installment.fromMap(data, id: doc.id);
  }

  Map<String, dynamic> _toFirestoreMap(Installment installment) {
    return {
      'name': installment.name,
      'amount': installment.amount,
      'dayOfMonth': installment.dayOfMonth,
      'category': installment.category,
      'startDate': Timestamp.fromDate(installment.startDate),
      'endDate': installment.endDate == null
          ? null
          : Timestamp.fromDate(installment.endDate!),
      'paidMonths': installment.paidMonths,
      'totalMonths': installment.totalMonths,
      'cancelled': installment.cancelled,
      'paidMonthsAtStart': installment.paidMonthsAtStart,
      'originalPrincipal': installment.originalPrincipal,
      'remainingAmountOverride': installment.remainingAmountOverride,
    };
  }
}
