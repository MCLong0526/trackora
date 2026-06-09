import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

class LocalStorage {
  static const expensesBoxName = 'trackora_expenses_v1';
  static const metaBoxName = 'trackora_meta_v1';
  static const installmentsBoxName = 'trackora_installments_v1';
  static const borrowLendingBoxName = 'trackora_borrow_lending_v1';
  static const savingPlansBoxName = 'trackora_saving_plans_v1';
  static const accountsBoxName = 'trackora_accounts_v1';
  static const peopleBoxName = 'trackora_people_v1';
  static const pendingSyncBoxName = 'trackora_pending_sync_v1';
  static const pendingDeletesBoxName = 'trackora_pending_deletes_v1';
  static const preciousMetalsBoxName = 'trackora_precious_metals_v1';
  static const travelGroupsBoxName = 'trackora_travel_groups_v1';
  static const travelExpensesBoxName = 'trackora_travel_expenses_v1';
  static const travelMembersBoxName = 'trackora_travel_members_v1';
  static const splitBillsBoxName = 'trackora_split_bills_v1';
  static const expenseGroupsBoxName = 'trackora_expense_groups_v1';
  static const expenseGroupItemsBoxName = 'trackora_expense_group_items_v1';
  static const stockInvestmentsBoxName = 'trackora_stock_investments_v1';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    if (!kIsWeb && !Hive.isBoxOpen(expensesBoxName)) {
      final dir = await _hiveDirectory();
      Hive.init(dir.path);
    }
    await _openBox(expensesBoxName);
    await _openBox(metaBoxName);
    await _openBox(installmentsBoxName);
    await _openBox(borrowLendingBoxName);
    await _openBox(savingPlansBoxName);
    await _openBox(accountsBoxName);
    await _openBox(peopleBoxName);
    await _openBox(pendingSyncBoxName);
    await _openBox(pendingDeletesBoxName);
    await _openBox(preciousMetalsBoxName);
    await _openBox(travelGroupsBoxName);
    await _openBox(travelExpensesBoxName);
    await _openBox(travelMembersBoxName);
    await _openBox(splitBillsBoxName);
    await _openBox(expenseGroupsBoxName);
    await _openBox(expenseGroupItemsBoxName);
    await _openBox(stockInvestmentsBoxName);
    _initialized = true;
  }

  static Box<dynamic> get expenses => Hive.box(expensesBoxName);

  static Box<dynamic> get meta => Hive.box(metaBoxName);

  static Box<dynamic> get installments => Hive.box(installmentsBoxName);

  static Box<dynamic> get borrowLending => Hive.box(borrowLendingBoxName);

  static Box<dynamic> get savingPlans => Hive.box(savingPlansBoxName);

  static Box<dynamic> get accounts => Hive.box(accountsBoxName);

  static Box<dynamic> get people => Hive.box(peopleBoxName);

  static Box<dynamic> get pendingSync => Hive.box(pendingSyncBoxName);

  static Box<dynamic> get pendingDeletes => Hive.box(pendingDeletesBoxName);

  static Box<dynamic> get preciousMetals => Hive.box(preciousMetalsBoxName);

  static Box<dynamic> get travelGroups => Hive.box(travelGroupsBoxName);

  static Box<dynamic> get travelExpenses => Hive.box(travelExpensesBoxName);

  static Box<dynamic> get travelMembers => Hive.box(travelMembersBoxName);

  static Box<dynamic> get splitBills => Hive.box(splitBillsBoxName);

  static Box<dynamic> get expenseGroups => Hive.box(expenseGroupsBoxName);

  static Box<dynamic> get expenseGroupItems => Hive.box(expenseGroupItemsBoxName);

  static Box<dynamic> get stockInvestments => Hive.box(stockInvestmentsBoxName);

  static Future<void> _openBox(String name) async {
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
  }

  static Future<Directory> _hiveDirectory() async {
    final home = Platform.environment['HOME'];
    final basePath = home != null && home.isNotEmpty
        ? '$home/Library/Application Support/Trackora/hive'
        : '${Directory.systemTemp.path}/trackora_hive';
    final dir = Directory(basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
