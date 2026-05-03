import '../models/saving_plan.dart';

/// Storage-neutral contract for saving plans + their contributions
/// (contributions are persisted inline on the plan record).
abstract class SavingPlanRepository {
  Stream<List<SavingPlan>> getAll(String userId);

  Future<void> add(String userId, SavingPlan plan);

  Future<void> update(String userId, SavingPlan plan);

  Future<void> delete(String userId, String id);
}
