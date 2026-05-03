import 'package:hive_flutter/hive_flutter.dart';

class LocalStorage {
  static const expensesBoxName = 'trackora_expenses_v1';
  static const metaBoxName = 'trackora_meta_v1';
  static const installmentsBoxName = 'trackora_installments_v1';
  static const borrowLendingBoxName = 'trackora_borrow_lending_v1';
  static const savingPlansBoxName = 'trackora_saving_plans_v1';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    await Hive.initFlutter();
    await _openBox(expensesBoxName);
    await _openBox(metaBoxName);
    await _openBox(installmentsBoxName);
    await _openBox(borrowLendingBoxName);
    await _openBox(savingPlansBoxName);
    _initialized = true;
  }

  static Box<dynamic> get expenses => Hive.box(expensesBoxName);

  static Box<dynamic> get meta => Hive.box(metaBoxName);

  static Box<dynamic> get installments => Hive.box(installmentsBoxName);

  static Box<dynamic> get borrowLending => Hive.box(borrowLendingBoxName);

  static Box<dynamic> get savingPlans => Hive.box(savingPlansBoxName);

  static Future<void> _openBox(String name) async {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
  }
}
