import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

class AddEditAccountScreen extends ConsumerStatefulWidget {
  final Account? account;
  const AddEditAccountScreen({super.key, this.account});

  @override
  ConsumerState<AddEditAccountScreen> createState() =>
      _AddEditAccountScreenState();
}

class _AddEditAccountScreenState extends ConsumerState<AddEditAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();

  AccountType _type = AccountType.cash;
  bool _saving = false;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final a = widget.account!;
      _nameController.text = a.name;
      _balanceController.text = a.openingBalance > 0
          ? a.openingBalance.toStringAsFixed(2)
          : '';
      _type = a.type;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final repo = ref.read(accountRepositoryProvider);

    try {
      final openingBalance =
          double.tryParse(_balanceController.text) ?? 0.0;
      final now = DateTime.now();

      if (_isEdit) {
        final updated = widget.account!.copyWith(
          name: _nameController.text.trim(),
          type: _type,
          openingBalance: openingBalance,
        );
        await repo.update(user.uid, updated);
      } else {
        final account = Account(
          id: '',
          name: _nameController.text.trim(),
          type: _type,
          openingBalance: openingBalance,
          createdAt: now,
        );
        await repo.add(user.uid, account);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'All transactions linked to this account will lose their account reference. This cannot be undone.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(accountRepositoryProvider)
        .delete(user.uid, widget.account!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEdit ? 'Edit Account' : 'New Account'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(CupertinoIcons.delete, size: 20),
              color: AppColors.expense,
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Account Type',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ),
              _typeSelector(brand),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Account name (e.g. Maybank, GrabPay)',
                  labelText: 'Name',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  labelText: 'Opening Balance (optional)',
                ),
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    if (double.tryParse(v) == null) {
                      return 'Enter a valid amount';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Opening balance is the amount already in this account before tracking starts.',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(_isEdit ? 'Update Account' : 'Create Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeSelector(BrandColors brand) {
    return SectionCard(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: AccountType.values
            .map((t) => _typeChip(t, brand))
            .toList(),
      ),
    );
  }

  Widget _typeChip(AccountType type, BrandColors brand) {
    final selected = _type == type;
    final selectedFg = foregroundOn(brand.accentDark);
    final iconData = _iconFor(type);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _type = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? brand.accentDark : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Column(
            children: [
              Icon(
                iconData,
                size: 20,
                color: selected ? selectedFg : brand.inkSoft,
              ),
              const SizedBox(height: 4),
              Text(
                type.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? selectedFg : brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return CupertinoIcons.building_2_fill;
      case AccountType.eWallet:
        return CupertinoIcons.device_phone_portrait;
      case AccountType.cash:
        return CupertinoIcons.money_dollar_circle_fill;
    }
  }
}
