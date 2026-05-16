import '../models/stock_investment.dart';

abstract class StockInvestmentRepository {
  Stream<List<StockInvestment>> getAll(String userId);
  Future<void> add(String userId, StockInvestment investment);
  Future<void> update(String userId, StockInvestment investment);
  Future<void> delete(String userId, String id);
}
