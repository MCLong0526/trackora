import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../models/account.dart';
import '../../repositories/firebase_account_repository.dart';
import '../../repositories/local_account_repository.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/currency_picker.dart';
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

const kCommonCreditCards = [
  // Malaysia
  'Maybank Visa', 'CIMB Visa', 'Public Bank Visa', 'RHB Visa',
  'Hong Leong Visa', 'AmBank Visa', 'Alliance Bank Visa',
  'Maybank Mastercard', 'CIMB Mastercard', 'Public Bank Mastercard',
  // Singapore
  'DBS Cashback Card', 'OCBC 365 Card', 'UOB One Card',
  // US
  'Chase Freedom', 'Amex Gold', 'Capital One Venture', 'Discover It',
  // Global
  'Visa', 'Mastercard', 'American Express', 'UnionPay',
  _kCustomLabel,
];

const _assetTypes = [AccountType.bank, AccountType.eWallet, AccountType.cash];
const _extraAssetTypes = [AccountType.investment, AccountType.savings, AccountType.crypto, AccountType.forex];

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
  double _animatedBalance = 0;
  String _currencyCode = 'MYR'; // will be loaded from prefs in initState

  // Optional interest accrual (asset accounts only).
  final _interestController = TextEditingController();
  String _interestPeriod = 'daily'; // daily | monthly | yearly

  bool get _isEdit => widget.account != null;

  bool get _hasProviderList =>
      _type == AccountType.bank ||
      _type == AccountType.eWallet ||
      _type == AccountType.creditCard;

  List<String> get _providers {
    if (_type == AccountType.bank) return kCommonBanks;
    if (_type == AccountType.creditCard) return kCommonCreditCards;
    return kCommonWallets;
  }

  @override
  void initState() {
    super.initState();
    // Load main currency as default, then override with account's currency
    PrefsService().currencyCode().then((code) {
      if (mounted && !_isEdit) setState(() => _currencyCode = code);
    });
    if (_isEdit) {
      final a = widget.account!;
      _type = a.type;
      if (a.currencyCode != null) _currencyCode = a.currencyCode!;

      final displayBalance =
          _type.isLiability ? a.openingBalance.abs() : a.openingBalance;
      _balanceController.text =
          displayBalance > 0 ? displayBalance.toStringAsFixed(2) : '';
      _animatedBalance = displayBalance > 0 ? displayBalance : 0;

      if (_hasProviderList) {
        final providers = _providers;
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

      final rate = a.interestRatePercent;
      if (rate != null && rate > 0) {
        _interestController.text =
            rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : '$rate';
      }
      if (a.interestPeriod != null) _interestPeriod = a.interestPeriod!;
    }
    _nameController.addListener(_onNameChanged);
    _customNameController.addListener(_onNameChanged);
    _balanceController.addListener(_onBalanceChanged);
  }

  void _onNameChanged() => setState(() {});
  void _onBalanceChanged() {
    final v = double.tryParse(_balanceController.text) ?? 0.0;
    setState(() => _animatedBalance = v);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _customNameController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  String get _resolvedName {
    if (!_hasProviderList) return _nameController.text.trim();
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
      final enteredBalance = double.tryParse(_balanceController.text) ?? 0.0;
      final openingBalance =
          _type.isLiability ? -enteredBalance.abs() : enteredBalance;
      final now = DateTime.now();

      // Interest only applies to asset accounts.
      final interestRate = double.tryParse(_interestController.text.trim());
      final hasInterest =
          !_type.isLiability && interestRate != null && interestRate > 0;

      if (_isEdit) {
        final existing = widget.account!;
        final wasInterest = (existing.interestRatePercent ?? 0) > 0;
        final updated = existing.copyWith(
          name: _resolvedName,
          type: _type,
          openingBalance: openingBalance,
          currencyCode: _currencyCode,
          interestRatePercent: hasInterest ? interestRate : null,
          interestPeriod: hasInterest ? _interestPeriod : null,
          // Keep the existing checkpoint if interest was already on; start
          // accruing from now if newly enabled; clear it if turned off.
          lastInterestAt: hasInterest
              ? (wasInterest ? (existing.lastInterestAt ?? now) : now)
              : null,
        );
        await repo.update(user.uid, updated);
      } else {
        final account = Account(
          id: '',
          name: _resolvedName,
          type: _type,
          openingBalance: openingBalance,
          createdAt: now,
          currencyCode: _currencyCode,
          interestRatePercent: hasInterest ? interestRate : null,
          interestPeriod: hasInterest ? _interestPeriod : null,
          lastInterestAt: hasInterest ? now : null,
        );
        await repo.add(user.uid, account);
      }
      if (mounted) {
        AppToast.show(
          context,
          _isEdit ? 'Account updated' : 'Account created',
          type: AppToastType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Failed to save account',
          type: AppToastType.error,
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
        title: Text(context.t('account.deleteAccount')),
        content: Text(context.t('account.deleteConfirm')),
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
    final accountId = widget.account!.id;
    final isOnline = ref.read(isOnlineProvider);
    // Always delete from local Hive immediately.
    await LocalAccountRepository().delete(user.uid, accountId);
    if (isOnline) {
      try {
        await FirebaseAccountRepository().delete(user.uid, accountId);
      } catch (_) {
        await SyncService.markEntityPendingDelete(user.uid, 'account', accountId);
      }
    } else {
      await SyncService.markEntityPendingDelete(user.uid, 'account', accountId);
    }
    if (mounted) {
      AppToast.show(context, 'Account deleted', type: AppToastType.success);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.xmark, size: 17, color: brand.ink),
          ),
        ),
        title: Text(
          _isEdit ? context.t('account.editTitle') : context.t('account.newTitle'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: const [],
      ),
      body: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (_isEdit) ...[
                _livePreview(),
                const SizedBox(height: 22),
              ],
              _sectionLabel(context.t('account.typeLabel'), brand),
              const SizedBox(height: 10),
              _typeSelector(brand),
              const SizedBox(height: 22),
              _sectionLabel(
                _hasProviderList
                    ? (_type == AccountType.bank
                        ? 'Bank'
                        : _type == AccountType.creditCard
                            ? 'Credit Card'
                            : 'E-Wallet')
                    : context.t('account.nameLabel'),
                brand,
              ),
              const SizedBox(height: 10),
              _nameCard(brand),
              const SizedBox(height: 22),
              _sectionLabel(
                _type.isLiability ? 'Balance Owed' : 'Opening Balance',
                brand,
              ),
              const SizedBox(height: 10),
              _balanceCard(brand),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  _type.isLiability
                      ? 'Enter how much you currently owe on this account.'
                      : 'Opening balance is the amount already in this account before tracking starts.',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ),
              const SizedBox(height: 22),
              _sectionLabel('Account Currency', brand),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: CurrencyPickerTile(
                    value: _currencyCode,
                    label: 'Currency',
                    onChanged: (code) => setState(() => _currencyCode = code),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Balances will be converted to your main currency for totals.',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ),
              if (!_type.isLiability) ...[
                const SizedBox(height: 22),
                _sectionLabel(context.t('account.interest'), brand),
                const SizedBox(height: 10),
                _interestCard(brand),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    context.t('account.interestHint'),
                    style: TextStyle(fontSize: 12, color: brand.inkSoft),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _saving
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(
                          _isEdit ? context.t('account.updateBtn') : context.t('account.createBtn'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 32),
                _dangerZone(brand),
              ],
            ],
          ),
        ),
      ),
        ),
    );
  }

  List<Color> _cardGradient(AccountType t) {
    switch (t) {
      case AccountType.bank:
        return [const Color(0xFFCFE0FF), const Color(0xFFA8C5F5)];
      case AccountType.eWallet:
        return [const Color(0xFFD2F0DD), const Color(0xFFA8DDC0)];
      case AccountType.cash:
        return [const Color(0xFFFBE9C2), const Color(0xFFF2D38C)];
      case AccountType.investment:
        return [const Color(0xFFD3F5E0), const Color(0xFFA8E8C2)];
      case AccountType.savings:
        return [const Color(0xFFD0EEFF), const Color(0xFFA5D5F5)];
      case AccountType.crypto:
        return [const Color(0xFFFFE8CC), const Color(0xFFFFD099)];
      case AccountType.forex:
        return [const Color(0xFFEAD5FF), const Color(0xFFD0A8F5)];
      case AccountType.creditCard:
        return [const Color(0xFFFCD7D7), const Color(0xFFF5B6B6)];
      case AccountType.loan:
        return [const Color(0xFFFFE3BC), const Color(0xFFFFCD83)];
      case AccountType.mortgage:
        return [const Color(0xFFEDE5D8), const Color(0xFFD9CAAB)];
      case AccountType.bnpl:
        return [const Color(0xFFE4D7F5), const Color(0xFFCBB3E8)];
      case AccountType.otherLiability:
        return [const Color(0xFFFAD3D3), const Color(0xFFF0ADAD)];
    }
  }

  Color _cardInk(AccountType t) {
    switch (t) {
      case AccountType.bank:
        return const Color(0xFF1E3F8A);
      case AccountType.eWallet:
        return const Color(0xFF1B5A3D);
      case AccountType.cash:
        return const Color(0xFF7A5512);
      case AccountType.investment:
        return const Color(0xFF1A5E36);
      case AccountType.savings:
        return const Color(0xFF1A4A6E);
      case AccountType.crypto:
        return const Color(0xFF8A4E04);
      case AccountType.forex:
        return const Color(0xFF4E2A8A);
      case AccountType.creditCard:
        return const Color(0xFF922C2C);
      case AccountType.loan:
        return const Color(0xFF8A5A04);
      case AccountType.mortgage:
        return const Color(0xFF6B4D2A);
      case AccountType.bnpl:
        return const Color(0xFF5C3A9E);
      case AccountType.otherLiability:
        return const Color(0xFF7A4040);
    }
  }

  Widget _livePreview() {
    final gradient = _cardGradient(_type);
    final ink = _cardInk(_type);
    final accent = _accentColorFor(_type);
    final previewName = _resolvedName.isEmpty
        ? (widget.account?.name ?? _type.label)
        : _resolvedName;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 160,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -60,
            top: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: -20,
            bottom: -50,
            child: Text(
              _type.label.toUpperCase().substring(0, 1),
              style: TextStyle(
                fontSize: 160,
                fontWeight: FontWeight.w700,
                color: accent.withValues(alpha: 0.10),
                height: 1,
              ),
            ),
          ),
          Positioned(
            top: -40,
            left: -20,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.40),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _type.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    color: ink.withValues(alpha: 0.60),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  previewName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Text(
                  _type.isLiability ? 'BALANCE OWED' : context.t('account.balance'),
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.3,
                    color: ink.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _animatedBalance),
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  builder: (ctx, v, _) {
                    final sym = kSupportedCurrencies[_currencyCode] ?? _currencyCode;
                    final sep = sym.length > 1 ? ' ' : '';
                    return Text(
                      '$sym$sep${NumberFormat('#,##0.00').format(v)}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        letterSpacing: -0.3,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerZone(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(context.t('account.dangerZone'), brand),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.expense.withValues(alpha: 0.18),
              width: 1,
            ),
            ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              onTap: _delete,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.expense.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        CupertinoIcons.delete,
                        size: 16,
                        color: AppColors.expense,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('account.deleteAccount'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.expense,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            context.t('account.dangerDesc'),
                            style: TextStyle(
                              fontSize: 11,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: AppColors.expense.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: brand.inkSoft,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _nameCard(BrandColors brand) {
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 46),
      color: brand.divider,
    );

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          children: [
            if (_hasProviderList) ...[
              _providerRow(brand),
              if (_useCustomName) ...[
                divider,
                _customNameRow(brand),
              ],
            ] else ...[
              _freeNameRow(brand),
            ],
          ],
        ),
      ),
    );
  }

  Widget _providerRow(BrandColors brand) {
    final label = _type == AccountType.bank
        ? 'Bank'
        : _type == AccountType.creditCard
            ? 'Credit Card'
            : 'E-Wallet';
    final display = _useCustomName
        ? 'Custom'
        : (_selectedProvider ?? 'Select $label');

    return InkWell(
      onTap: () => _showProviderPicker(brand),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _accentColorFor(_type).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconFor(_type),
                size: 16,
                color: _accentColorFor(_type),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              ),
            ),
            Text(
              display,
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }

  Widget _customNameRow(BrandColors brand) {
    final hint = _type == AccountType.bank
        ? 'Enter bank name'
        : _type == AccountType.creditCard
            ? 'Enter card name'
            : 'Enter e-wallet name';

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(CupertinoIcons.pencil, size: 18, color: brand.inkSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _customNameController,
              textCapitalization: TextCapitalization.words,
              autofocus: false,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: brand.inkSoft, fontSize: 15),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.t('account.enterName');
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _freeNameRow(BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconFor(_type), size: 18, color: _accentColorFor(_type)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 15),
              decoration: InputDecoration(
                hintText: _type.namePlaceholder,
                hintStyle: TextStyle(color: brand.inkSoft, fontSize: 15),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return context.t('account.enterName');
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(BrandColors brand) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12),
          child: Row(
            children: [
              Icon(
                _type.isLiability
                    ? CupertinoIcons.minus_circle
                    : CupertinoIcons.money_dollar_circle,
                size: 18,
                color: _type.isLiability ? AppColors.expense : brand.inkSoft,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _balanceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: brand.inkSoft, fontSize: 15),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  validator: (v) {
                    if (v != null && v.isNotEmpty) {
                      if (double.tryParse(v) == null) return 'Enter a valid amount';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _interestCard(BrandColors brand) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.percent, size: 18, color: brand.inkSoft),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.t('account.interestRate'),
                  style: const TextStyle(fontSize: 15),
                ),
              ),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _interestController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(color: brand.inkSoft, fontSize: 15),
                    suffixText: '%',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _interestPeriodChip('daily', context.t('account.interestDaily'),
                  brand),
              const SizedBox(width: 6),
              _interestPeriodChip(
                  'monthly', context.t('account.interestMonthly'), brand),
              const SizedBox(width: 6),
              _interestPeriodChip(
                  'yearly', context.t('account.interestYearly'), brand),
            ],
          ),
        ],
      ),
    );
  }

  Widget _interestPeriodChip(String value, String label, BrandColors brand) {
    final selected = _interestPeriod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _interestPeriod = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppActionBlue.color.withValues(alpha: 0.12)
                : brand.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppActionBlue.color : brand.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppActionBlue.color : brand.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _typeSelector(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupLabel('ASSET', brand),
        const SizedBox(height: 8),
        SectionCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              Row(
                children: _assetTypes.map((t) => _typeChip(t, brand)).toList(),
              ),
              const SizedBox(height: 4),
              Row(
                children: _extraAssetTypes.map((t) => _typeChip(t, brand)).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _groupLabel('LIABILITY', brand),
        const SizedBox(height: 8),
        SectionCard(
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              Row(
                children: [
                  _typeChip(AccountType.creditCard, brand),
                  _typeChip(AccountType.loan, brand),
                  _typeChip(AccountType.mortgage, brand),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _typeChip(AccountType.bnpl, brand),
                  _typeChip(AccountType.otherLiability, brand),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _groupLabel(String text, BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: brand.inkSoft,
        ),
      ),
    );
  }

  Widget _typeChip(AccountType type, BrandColors brand) {
    final selected = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          _selectedProvider = null;
          _useCustomName = false;
          _customNameController.clear();
          _nameController.clear();
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? (type.isLiability
                    ? AppColors.expense.withValues(alpha: 0.85)
                    : brand.accentDark)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Column(
            children: [
              Icon(
                _iconFor(type),
                size: 18,
                color: selected
                    ? (type.isLiability ? Colors.white : foregroundOn(brand.accentDark))
                    : brand.inkSoft,
              ),
              const SizedBox(height: 4),
              Text(
                type.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? (type.isLiability ? Colors.white : foregroundOn(brand.accentDark))
                      : brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showProviderPicker(BrandColors brand) {
    FocusScope.of(context).unfocus();
    final allProviders = List<String>.from(_providers);
    final label = _type == AccountType.bank
        ? 'Select Bank'
        : _type == AccountType.creditCard
            ? 'Select Credit Card'
            : 'Select E-Wallet';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: brand.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = query.isEmpty
                ? allProviders
                : allProviders
                    .where((p) =>
                        p.toLowerCase().contains(query.toLowerCase()))
                    .toList();

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.72,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: brand.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          autofocus: false,
                          onChanged: (v) => setSheetState(() => query = v),
                          style: TextStyle(fontSize: 14, color: brand.ink),
                          decoration: InputDecoration(
                            hintText: 'Search…',
                            hintStyle: TextStyle(color: brand.inkSoft, fontSize: 14),
                            prefixIcon: Icon(CupertinoIcons.search, size: 16, color: brand.inkSoft),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: brand.inkSoft.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final isCustom = p == _kCustomLabel;
                          final isSelected = isCustom
                              ? _useCustomName
                              : _selectedProvider == p && !_useCustomName;

                          return ListTile(
                            leading: isCustom
                                ? Icon(CupertinoIcons.pencil, color: brand.inkSoft, size: 18)
                                : Icon(
                                    _iconFor(_type),
                                    color: _accentColorFor(_type),
                                    size: 18,
                                  ),
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
                                if (!isCustom) _customNameController.clear();
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
      },
    ).whenComplete(() {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) FocusScope.of(context).unfocus();
        });
      }
    });
  }

  IconData _iconFor(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return PhosphorIconsFill.bank;
      case AccountType.eWallet:
        return PhosphorIconsFill.deviceMobile;
      case AccountType.cash:
        return PhosphorIconsFill.currencyDollar;
      case AccountType.investment:
        return PhosphorIconsFill.chartLineUp;
      case AccountType.savings:
        return PhosphorIconsFill.piggyBank;
      case AccountType.crypto:
        return PhosphorIconsFill.currencyBtc;
      case AccountType.forex:
        return PhosphorIconsFill.globe;
      case AccountType.creditCard:
        return CupertinoIcons.creditcard_fill;
      case AccountType.loan:
        return PhosphorIconsFill.receipt;
      case AccountType.mortgage:
        return CupertinoIcons.house_fill;
      case AccountType.bnpl:
        return CupertinoIcons.cart_fill;
      case AccountType.otherLiability:
        return CupertinoIcons.minus_circle_fill;
    }
  }

  Color _accentColorFor(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return const Color(0xFF2A6FB5);
      case AccountType.eWallet:
        return const Color(0xFF1F7A60);
      case AccountType.cash:
        return const Color(0xFFA0801C);
      case AccountType.investment:
        return const Color(0xFF2E9E5A);
      case AccountType.savings:
        return const Color(0xFF2E7EB5);
      case AccountType.crypto:
        return const Color(0xFFE8820E);
      case AccountType.forex:
        return const Color(0xFF7F4FD4);
      case AccountType.creditCard:
        return const Color(0xFFB03060);
      case AccountType.loan:
        return const Color(0xFF9C4A1A);
      case AccountType.mortgage:
        return const Color(0xFF6B4D2A);
      case AccountType.bnpl:
        return const Color(0xFF5C3A9E);
      case AccountType.otherLiability:
        return const Color(0xFF7A4040);
    }
  }
}
