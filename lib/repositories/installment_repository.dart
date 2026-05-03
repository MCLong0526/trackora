import '../models/installment.dart';

abstract class InstallmentRepository {
  Stream<List<Installment>> getAll(String userId);

  Future<void> add(String userId, Installment installment);

  Future<void> update(String userId, Installment installment);

  Future<void> delete(String userId, String id);
}
