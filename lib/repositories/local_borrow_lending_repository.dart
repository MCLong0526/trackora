import 'package:hive/hive.dart';

import '../models/borrow_lending.dart';
import 'borrow_lending_repository.dart';
import 'local_storage.dart';

/// Hive-backed `BorrowLendingRepository`. Same key-prefixing strategy
/// as the other local repos: `{userId}:{recordId}` so local mode's
/// built-in offline user gets its own scope without colliding with
/// any future per-user data.
class LocalBorrowLendingRepository implements BorrowLendingRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _box => LocalStorage.borrowLending;

  @override
  Stream<List<BorrowLending>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<BorrowLending>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, BorrowLending record) async {
    await LocalStorage.init();
    final id = record.id.isEmpty ? _newId() : record.id;
    final saved = record.id == id ? record : record.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, BorrowLending record) async {
    await LocalStorage.init();
    if (record.id.isEmpty) return;
    await _box.put(_key(userId, record.id), _toStored(userId, record));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<BorrowLending> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<BorrowLending>(
          (data) => BorrowLending.fromMap(data, id: data['id'] as String),
        )
        .toList();
    // Newest first by creation time so the most recent borrow / lending
    // surfaces at the top of the list.
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, BorrowLending r) {
    return {...r.toMap(includeId: true), 'userId': userId};
  }

  String _key(String userId, String id) => '$userId:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
