import 'package:hive/hive.dart';

import '../models/saving_plan.dart';
import 'local_storage.dart';
import 'saving_plan_repository.dart';

class LocalSavingPlanRepository implements SavingPlanRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _box => LocalStorage.savingPlans;

  @override
  Stream<List<SavingPlan>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<SavingPlan>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, SavingPlan plan) async {
    await LocalStorage.init();
    final id = plan.id.isEmpty ? _newId() : plan.id;
    final saved = plan.id == id ? plan : plan.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, SavingPlan plan) async {
    await LocalStorage.init();
    if (plan.id.isEmpty) return;
    await _box.put(_key(userId, plan.id), _toStored(userId, plan));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<SavingPlan> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<SavingPlan>(
          (data) => SavingPlan.fromMap(data, id: data['id'] as String),
        )
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, SavingPlan p) {
    return {...p.toMap(includeId: true), 'userId': userId};
  }

  String _key(String userId, String id) => '$userId:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
