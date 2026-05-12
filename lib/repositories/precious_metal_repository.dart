import '../models/precious_metal.dart';

abstract class PreciousMetalRepository {
  Stream<List<PreciousMetal>> getAll(String userId);
  Future<void> add(String userId, PreciousMetal metal);
  Future<void> update(String userId, PreciousMetal metal);
  Future<void> delete(String userId, String id);
}
