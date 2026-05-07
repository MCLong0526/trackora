import '../models/person.dart';
import '../repositories/person_repository.dart';

class PersonService {
  final PersonRepository _repository;
  PersonService(this._repository);

  Stream<List<Person>> getAll(String userId) => _repository.getAll(userId);

  Future<void> add(String userId, Person person) =>
      _repository.add(userId, person);

  Future<void> update(String userId, Person person) =>
      _repository.update(userId, person);

  Future<void> delete(String userId, String id) =>
      _repository.delete(userId, id);
}
