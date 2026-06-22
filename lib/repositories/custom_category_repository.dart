import '../models/custom_category.dart';

abstract class CustomCategoryRepository {
  Stream<List<CustomCategory>> getAll(String userId);

  Future<void> add(String userId, CustomCategory category);

  Future<void> update(String userId, CustomCategory category);

  Future<void> delete(String userId, String id);
}
