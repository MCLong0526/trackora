import 'package:hive/hive.dart';

import '../models/custom_category.dart';
import 'custom_category_repository.dart';
import 'local_storage.dart';

class LocalCustomCategoryRepository implements CustomCategoryRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _box => LocalStorage.customCategories;

  String _key(String userId, String id) => '$userId:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Stream<List<CustomCategory>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<CustomCategory>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, CustomCategory category) async {
    await LocalStorage.init();
    final id = category.id.isEmpty ? _newId() : category.id;
    final saved = category.id == id ? category : category.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, CustomCategory category) async {
    await LocalStorage.init();
    if (category.id.isEmpty) return;
    await _box.put(_key(userId, category.id), _toStored(userId, category));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<CustomCategory> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<CustomCategory>(
            (data) => CustomCategory.fromMap(data, id: data['id'] as String))
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, CustomCategory c) {
    return {...c.toMap(includeId: true), 'userId': userId};
  }
}
