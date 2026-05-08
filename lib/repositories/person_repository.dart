import '../models/person.dart';

abstract class PersonRepository {
  Stream<List<Person>> getAll(String userId);

  Future<void> add(String userId, Person person);

  Future<void> update(String userId, Person person);

  Future<void> delete(String userId, String id);
}
