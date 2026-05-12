import 'package:hive_flutter/hive_flutter.dart';

import '../models/precious_metal.dart';
import 'local_storage.dart';
import 'precious_metal_repository.dart';

class LocalPreciousMetalRepository implements PreciousMetalRepository {
  Box<dynamic> get _box => LocalStorage.preciousMetals;

  @override
  Stream<List<PreciousMetal>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<PreciousMetal>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, PreciousMetal metal) async {
    await LocalStorage.init();
    final id = metal.id.isEmpty ? _newId() : metal.id;
    final saved = metal.id == id ? metal : metal.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, PreciousMetal metal) async {
    await LocalStorage.init();
    if (metal.id.isEmpty) return;
    await _box.put(_key(userId, metal.id), _toStored(userId, metal));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<PreciousMetal> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<PreciousMetal>(
          (data) => PreciousMetal.fromMap(data, id: data['id'] as String),
        )
        .toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, PreciousMetal m) {
    return {...m.toMap(includeId: true), 'userId': userId};
  }

  String _key(String userId, String id) => '$userId:precious_metal:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
