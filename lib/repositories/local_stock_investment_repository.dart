import 'package:hive/hive.dart';

import '../models/stock_investment.dart';
import 'local_storage.dart';
import 'stock_investment_repository.dart';

/// Offline (Hive) implementation of [StockInvestmentRepository], mirroring the
/// other local repositories so stock investments work fully offline and sync
/// to Firestore on reconnect.
class LocalStockInvestmentRepository implements StockInvestmentRepository {
  Box<dynamic> get _box => LocalStorage.stockInvestments;

  @override
  Stream<List<StockInvestment>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<StockInvestment>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, StockInvestment investment) async {
    await LocalStorage.init();
    final id = investment.id.isEmpty ? _newId() : investment.id;
    final saved = investment.id == id ? investment : investment.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, StockInvestment investment) async {
    await LocalStorage.init();
    if (investment.id.isEmpty) return;
    await _box.put(_key(userId, investment.id), _toStored(userId, investment));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<StockInvestment> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<StockInvestment>(
          (data) => StockInvestment.fromMap(data, id: data['id'] as String),
        )
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, StockInvestment s) {
    return {...s.toMap(), 'id': s.id, 'userId': userId};
  }

  String _key(String userId, String id) => '$userId:stock:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
