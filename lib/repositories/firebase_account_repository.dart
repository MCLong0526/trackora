import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/account.dart';
import 'account_repository.dart';

class FirebaseAccountRepository implements AccountRepository {
  final FirebaseFirestore _db;

  FirebaseAccountRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      _db.collection('users').doc(userId).collection('accounts');

  @override
  Stream<List<Account>> getAll(String userId) {
    return _col(userId).snapshots().map((s) => s.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final ts = data['createdAt'];
          if (ts is Timestamp) data['createdAt'] = ts.toDate();
          return Account.fromMap(data, id: d.id);
        }).toList());
  }

  @override
  Future<void> add(String userId, Account account) async {
    final id = account.id.isEmpty ? null : account.id;
    if (id != null) {
      await _col(userId).doc(id).set(_toMap(account));
    } else {
      await _col(userId).add(_toMap(account));
    }
  }

  @override
  Future<void> update(String userId, Account account) async {
    // Deliberately excludes createdAt to preserve stable sort order.
    await _col(userId).doc(account.id).update({
      'name': account.name,
      'type': account.type.encode,
      'openingBalance': account.openingBalance,
      if (account.currencyCode != null) 'currencyCode': account.currencyCode,
    });
  }

  Future<void> upsert(String userId, Account account) async {
    if (account.id.isEmpty) {
      await add(userId, account);
      return;
    }
    await _col(userId)
        .doc(account.id)
        .set(_toMap(account), SetOptions(merge: true));
  }

  @override
  Future<void> delete(String userId, String accountId) async {
    await _col(userId).doc(accountId).delete();
  }

  Map<String, dynamic> _toMap(Account account) => {
    'name': account.name,
    'type': account.type.encode,
    'openingBalance': account.openingBalance,
    'createdAt': Timestamp.fromDate(account.createdAt),
    if (account.currencyCode != null) 'currencyCode': account.currencyCode,
  };
}
