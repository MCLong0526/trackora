import 'package:hive_flutter/hive_flutter.dart';

import '../models/installment.dart';
import 'installment_repository.dart';
import 'local_storage.dart';

class LocalInstallmentRepository implements InstallmentRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _installments => LocalStorage.installments;

  @override
  Stream<List<Installment>> getAll(String userId) async* {
    await LocalStorage.init();
    yield _readInstallments(userId);
    yield* _installments.watch().map<List<Installment>>(
      (_) => _readInstallments(userId),
    );
  }

  @override
  Future<void> add(String userId, Installment installment) async {
    await LocalStorage.init();
    final id = installment.id.isEmpty ? _newId() : installment.id;
    final saved = installment.id == id
        ? installment
        : installment.copyWith(id: id);
    await _installments.put(
      _installmentKey(userId, id),
      _toStoredMap(userId, saved),
    );
  }

  @override
  Future<void> update(String userId, Installment installment) async {
    await LocalStorage.init();
    if (installment.id.isEmpty) return;
    await _installments.put(
      _installmentKey(userId, installment.id),
      _toStoredMap(userId, installment),
    );
  }

  @override
  Future<void> delete(String userId, String id) async {
    await LocalStorage.init();
    await _installments.delete(_installmentKey(userId, id));
  }

  List<Installment> _readInstallments(String userId) {
    final installments = _installments.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<Installment>(
          (data) => Installment.fromMap(data, id: data['id'] as String),
        )
        .toList();

    installments.sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));

    return installments;
  }

  Map<String, dynamic> _toStoredMap(String userId, Installment installment) {
    return {...installment.toMap(includeId: true), 'userId': userId};
  }

  String _installmentKey(String userId, String installmentId) {
    return '$userId:$installmentId';
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
