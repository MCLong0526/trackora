import '../models/saving_plan.dart';
import '../repositories/local_saving_plan_repository.dart';
import '../repositories/saving_plan_repository.dart';
import 'sync_service.dart';

class SavingPlanService {
  final SavingPlanRepository _repo;
  SavingPlanService(this._repo);

  Stream<List<SavingPlan>> getAll(String userId) => _repo.getAll(userId);

  Future<void> add(String userId, SavingPlan plan) => _repo.add(userId, plan);

  Future<void> update(String userId, SavingPlan plan) =>
      _repo.update(userId, plan);

  Future<void> delete(String userId, String id) async {
    await _repo.delete(userId, id);
    // Always clean local Hive and record tombstone for sync
    await LocalSavingPlanRepository().delete(userId, id);
    await SyncService.markEntityPendingDelete(userId, 'plan', id);
  }

  /// Append a contribution. Bumps `updatedAt` so the list re-sorts.
  Future<void> addContribution(
    String userId,
    SavingPlan plan,
    SavingContribution c,
  ) {
    return _repo.update(
      userId,
      plan.copyWith(
        contributions: [...plan.contributions, c],
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> removeContribution(
    String userId,
    SavingPlan plan,
    String contributionId,
  ) {
    return _repo.update(
      userId,
      plan.copyWith(
        contributions:
            plan.contributions.where((c) => c.id != contributionId).toList(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markCompleted(String userId, SavingPlan plan) {
    return _repo.update(
      userId,
      plan.copyWith(manualCompleted: true, updatedAt: DateTime.now()),
    );
  }

  Future<void> setCancelled(String userId, SavingPlan plan, bool cancelled) {
    return _repo.update(
      userId,
      plan.copyWith(cancelled: cancelled, updatedAt: DateTime.now()),
    );
  }
}
