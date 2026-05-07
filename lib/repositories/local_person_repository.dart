import 'package:hive_flutter/hive_flutter.dart';

import '../models/person.dart';
import 'local_storage.dart';
import 'person_repository.dart';

class LocalPersonRepository implements PersonRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _box => LocalStorage.people;

  String _key(String userId, String id) => '$userId:$id';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  @override
  Stream<List<Person>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _read(userId);
    yield* _box.watch().map<List<Person>>((_) => _read(userId));
  }

  @override
  Future<void> add(String userId, Person person) async {
    await LocalStorage.init();
    final id = person.id.isEmpty ? _newId() : person.id;
    final saved = person.id == id ? person : person.copyWith(id: id);
    await _box.put(_key(userId, id), _toStored(userId, saved));
  }

  @override
  Future<void> update(String userId, Person person) async {
    await LocalStorage.init();
    if (person.id.isEmpty) return;
    await _box.put(_key(userId, person.id), _toStored(userId, person));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _box.delete(_key(userId, id));
  }

  List<Person> _read(String userId) {
    final list = _box.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<Person>(
          (data) => Person.fromMap(data, id: data['id'] as String),
        )
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Map<String, dynamic> _toStored(String userId, Person p) {
    return {...p.toMap(includeId: true), 'userId': userId};
  }
}
