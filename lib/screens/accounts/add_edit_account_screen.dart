import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

const _kCustomLabel = 'Other / Custom';

const kCommonBanks = [
  // Malaysia
  'Maybank', 'CIMB Bank', 'Public Bank', 'RHB Bank', 'Hong Leong Bank',
  'AmBank', 'Bank Islam', 'Bank Rakyat', 'BSN', 'Affin Bank',
  // Singapore
  'DBS Bank', 'OCBC Bank', 'UOB', 'Standard Chartered',
  // Indonesia
  'Bank Central Asia (BCA)', 'Bank Mandiri', 'Bank BNI', 'Bank BRI',
  'Bank Danamon', 'Bank CIMB Niaga',
  // Thailand
  'Bangkok Bank', 'Kasikorn Bank (KBank)', 'SCB', 'Krungthai Bank',
  // Philippines
  'BDO Unibank', 'Metrobank', 'BPI', 'Land Bank', 'Security Bank',
  // India
  'State Bank of India (SBI)', 'HDFC Bank', 'ICICI Bank', 'Axis Bank',
  'Kotak Mahindra Bank', 'Punjab National Bank',
  // China
  'Industrial and Commercial Bank of China (ICBC)',
  'China Construction Bank', 'Agricultural Bank of China', 'Bank of China',
  // US
  'Chase', 'Bank of America', 'Wells Fargo', 'Citibank', 'Goldman Sachs',
  'US Bank', 'Capital One', 'TD Bank',
  // UK
  'HSBC', 'Barclays', 'Lloyds Bank', 'NatWest', 'Santander UK',
  // Australia
  'Commonwealth Bank', 'ANZ', 'Westpac', 'NAB',
  // Global
  'Deutsche Bank', 'BNP Paribas', 'Credit Suisse', 'ING', 'Rabobank',
  _kCustomLabel,
];

const kCommonWallets = [
  // Malaysia / SEA
  'Touch \'n Go eWallet', 'GrabPay', 'Boost', 'ShopeePay', 'BigPay',
  'MAE by Maybank', 'FPX', 'Razer Pay',
  // Indonesia
  'GoPay', 'OVO', 'Dana', 'LinkAja',
  // Thailand
  'PromptPay', 'TrueMoney Wallet', 'Rabbit LINE Pay',
  // Philippines
  'GCash', 'PayMaya', 'Coins.ph',
  // India
  'Paytm', 'PhonePe', 'Google Pay India', 'Amazon Pay India',
  // Global
  'PayPal', 'Apple Pay', 'Google Pay', 'Samsung Pay', 'Venmo', 'Cash App',
  // China
  'Alipay', 'WeChat Pay',
  // Europe
  'Revolut', 'N26', 'Wise', 'Klarna',
  _kCustomLabel,
];

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
  final _customNameController = TextEditingController();

  AccountType _type = AccountType.cash;
  String? _selectedProvider;
  bool _useCustomName = false;
  bool _saving = false;

  bool get _isEdit => widget.account != null;

  List<String> get _providers =>
      _type == AccountType.bank ? kCommonBanks : kCommonWallets;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final a = widget.account!;
      _type = a.type;
      _balanceController.text = a.openingBalance > 0
          ? a.openingBalance.toStringAsFixed(2)
          : '';

      if (_type == AccountType.bank || _type == AccountType.eWallet) {
        final providers = _type == AccountType.bank ? kCommonBanks : kCommonWallets;
        if (providers.contains(a.name)) {
          _selectedProvider = a.name;
          _useCustomName = false;
        } else {
          _selectedProvider = _kCustomLabel;
          _useCustomName = true;
          _customNameController.text = a.name;
        }
      } else {
        _nameController.text = a.name;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _customNameController.dispose();
    super.dispose();
  }

  String get _resolvedName {
    if (_type == AccountType.cash) return _nameController.text.trim();
    if (_useCustomName) return _customNameController.text.trim();
    return _selectedProvider ?? '';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() => _saving = false);
      return;
    }
    final repo = ref.read(accountRepositoryProvider);

    try {
      final openingBalance = double.tryParse(_balanceController.text) ?? 0.0;
      final now = DateTime.now();

      if (_isEdit) {
        final updated = widget.account!.copyWith(
          name: _resolvedName,
          type: _type,
          openingBalance: openingBalance,
        );
        await repo.update(user.uid, updated);
      } else {
        final account = Account(
          id: '',
          name: _resolvedName,
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
              if (_type == AccountType.bank || _type == AccountType.eWallet) ...[
                _providerPicker(brand),
                if (_useCustomName) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _customNameController,
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: _type == AccountType.bank
                          ? 'Enter bank name'
                          : 'Enter e-wallet name',
                      labelText: _type == AccountType.bank ? 'Bank Name' : 'E-Wallet Name',
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      return null;
                    },
                  ),
                ],
              ] else ...[
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'e.g. My Wallet, Piggy Bank',
                    labelText: 'Account Name',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
              ],
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

  Widget _providerPicker(BrandColors brand) {
    final label = _type == AccountType.bank ? 'Bank' : 'E-Wallet';
    final display = _useCustomName
        ? 'Other / Custom'
        : (_selectedProvider ?? 'Select $label');

    return SectionCard(
      onTap: () => _showProviderPicker(brand),
      child: Row(
        children: [
          Icon(
            _type == AccountType.bank
                ? CupertinoIcons.building_2_fill
                : CupertinoIcons.device_phone_portrait,
            color: _type == AccountType.bank
                ? const Color(0xFF2A6FB5)
                : const Color(0xFF1F7A60),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Select $label',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(display, style: TextStyle(color: brand.inkSoft)),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_down, size: 14, color: brand.inkSoft),
        ],
      ),
    );
  }

  void _showProviderPicker(BrandColors brand) {
    final providers = List<String>.from(_providers);
    final title = _type == AccountType.bank ? 'Select Bank' : 'Select E-Wallet';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: providers.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: brand.inkSoft.withOpacity(0.12),
                    ),
                    itemBuilder: (context, index) {
                      final p = providers[index];
                      final isCustom = p == _kCustomLabel;
                      final isSelected = isCustom
                          ? _useCustomName
                          : _selectedProvider == p && !_useCustomName;

                      return ListTile(
                        title: Text(
                          p,
                          style: TextStyle(
                            color: brand.ink,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                          CupertinoIcons.checkmark_alt,
                          color: brand.accentDark,
                        )
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedProvider = p;
                            _useCustomName = isCustom;

                            if (!isCustom) {
                              _customNameController.clear();
                            }
                          });

                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
    // final selectedFg = foregroundOn(brand.accentDark);
    final selectedFg = Colors.white;
    final iconData = _iconFor(type);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          _selectedProvider = null;
          _useCustomName = false;
          _customNameController.clear();
        }),
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
                    color: selected ? Colors.white : brand.ink,
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
