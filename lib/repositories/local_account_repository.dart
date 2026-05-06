import 'package:hive_flutter/hive_flutter.dart';

import '../models/account.dart';
import 'account_repository.dart';
import 'local_storage.dart';

class LocalAccountRepository implements AccountRepository {
  Box<dynamic> get _box => LocalStorage.accounts;

  @override
  Stream<List<Account>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<Account>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, Account account) async {
    await LocalStorage.init();
    final id = account.id.isEmpty ? _newId() : account.id;
    final saved = account.id == id ? account : account.copyWith(id: id);
    await _box.put(_key(userId, id), _toMap(userId, saved));
  }

  @override
  Future<void> update(String userId, Account account) async {
    await LocalStorage.init();
    if (account.id.isEmpty) return;
    await _box.put(_key(userId, account.id), _toMap(userId, account));
  }

  @override
  Future<void> delete(String userId, String accountId) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, accountId));
  }

  List<Account> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<Account>((data) => Account.fromMap(data, id: data['id'] as String))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Map<String, dynamic> _toMap(String userId, Account account) {
    return {...account.toMap(includeId: true), 'userId': userId};
  }

  String _key(String userId, String id) => '$userId:account:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
