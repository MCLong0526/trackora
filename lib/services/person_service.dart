import '../models/person.dart';
import '../repositories/local_person_repository.dart';
import '../repositories/person_repository.dart';
import 'sync_service.dart';

class PersonService {
  final PersonRepository _repository;
  PersonService(this._repository);

  Stream<List<Person>> getAll(String userId) => _repository.getAll(userId);

  Future<void> add(String userId, Person person) =>
      _repository.add(userId, person);

  Future<void> update(String userId, Person person) =>
      _repository.update(userId, person);

  Future<void> delete(String userId, String id) async {
    await _repository.delete(userId, id);
    await LocalPersonRepository().delete(userId, id);
    await SyncService.markEntityPendingDelete(userId, 'person', id);
  }
}
