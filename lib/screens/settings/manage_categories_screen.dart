import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/category_catalog.dart';
import '../../models/custom_category.dart';
import '../../repositories/firebase_custom_category_repository.dart';
import '../../repositories/local_custom_category_repository.dart';
import '../../services/i18n.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fading_edge_list.dart';
import '../../widgets/pill_tabs.dart';

/// Lets the user view built-in categories and create / edit / delete their own
/// custom expense and income categories (name + icon + colour).
class ManageCategoriesScreen extends ConsumerStatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  ConsumerState<ManageCategoriesScreen> createState() =>
      _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState
    extends ConsumerState<ManageCategoriesScreen> {
  bool _income = false;

  List<String> get _defaults =>
      _income ? kDefaultIncomeCategories : kDefaultExpenseCategories;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final allCustom =
        ref.watch(customCategoriesProvider).valueOrNull ?? const [];
    final custom =
        allCustom.where((c) => c.isIncome == _income).toList();

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          context.t('settings.categories'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.add_circled, color: brand.ink),
            onPressed: () => _openEditor(allCustom),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PillTabs(
              tabs: [
                context.t('expense.expense'),
                context.t('expense.income'),
              ],
              selectedIndex: _income ? 1 : 0,
              onChanged: (i) => setState(() => _income = i == 1),
            ),
            const SizedBox(height: 22),
            _sectionLabel(context.t('category.yourCategories'), brand),
            const SizedBox(height: 10),
            if (custom.isEmpty)
              _emptyCard(brand)
            else
              ...custom.map((c) => _customRow(c, allCustom, brand)),
            const SizedBox(height: 22),
            _sectionLabel(context.t('category.builtIn'), brand),
            const SizedBox(height: 10),
            _defaultsCard(brand),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => _openEditor(allCustom),
                icon: const Icon(CupertinoIcons.add, size: 16),
                label: Text(context.t('category.addCategory')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, BrandColors brand) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: brand.inkSoft,
          ),
        ),
      );

  Widget _emptyCard(BrandColors brand) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Center(
          child: Text(
            context.t('category.emptyHint'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
        ),
      );

  Widget _customRow(
      CustomCategory c, List<CustomCategory> all, BrandColors brand) {
    final style = customCategoryStyle(iconKey: c.iconKey, colorIndex: c.colorIndex);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card)),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: style.background, shape: BoxShape.circle),
          child: Icon(style.icon, size: 18, color: style.accent),
        ),
        title: Text(c.name,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: brand.ink, fontSize: 15)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(CupertinoIcons.pencil, size: 18, color: brand.inkSoft),
              onPressed: () => _openEditor(all, editing: c),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.trash,
                  size: 18, color: AppColors.expense),
              onPressed: () => _confirmDelete(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultsCard(BrandColors brand) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _defaults.length; i++) ...[
            if (i > 0)
              Divider(height: 0.5, indent: 60, color: brand.divider),
            _defaultRow(_defaults[i], brand),
          ],
        ],
      ),
    );
  }

  Widget _defaultRow(String key, BrandColors brand) {
    final style = styleFor(key);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: style.background, shape: BoxShape.circle),
            child: Icon(style.icon, size: 16, color: style.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.categoryLabel(key),
              style: TextStyle(
                  fontSize: 14, color: brand.ink, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            context.t('category.builtInTag'),
            style: TextStyle(fontSize: 11, color: brand.inkSoft),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(CustomCategory c) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('category.deleteTitle')),
        content: Text(context.t('category.deleteConfirm')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final isOnline = ref.read(isOnlineProvider);
    await LocalCustomCategoryRepository().delete(uid, c.id);
    if (isOnline) {
      try {
        await FirebaseCustomCategoryRepository().delete(uid, c.id);
      } catch (_) {
        await SyncService.markEntityPendingDelete(uid, 'category', c.id);
      }
    } else {
      await SyncService.markEntityPendingDelete(uid, 'category', c.id);
    }
    if (mounted) {
      AppToast.show(context, context.t('category.deleted'),
          type: AppToastType.success);
    }
  }

  void _openEditor(List<CustomCategory> all, {CustomCategory? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryEditorSheet(
        income: _income,
        editing: editing,
        existing: all,
        onSaved: (cat, isEdit) => _save(cat, isEdit),
      ),
    );
  }

  Future<void> _save(CustomCategory cat, bool isEdit) async {
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    if (uid == null) return;
    final repo = ref.read(customCategoryRepositoryProvider);
    if (isEdit) {
      await repo.update(uid, cat);
    } else {
      await repo.add(uid, cat);
    }
    if (mounted) {
      AppToast.show(
        context,
        isEdit ? context.t('category.updated') : context.t('category.created'),
        type: AppToastType.success,
      );
    }
  }
}

class _CategoryEditorSheet extends StatefulWidget {
  final bool income;
  final CustomCategory? editing;
  final List<CustomCategory> existing;
  final void Function(CustomCategory cat, bool isEdit) onSaved;

  const _CategoryEditorSheet({
    required this.income,
    required this.editing,
    required this.existing,
    required this.onSaved,
  });

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _nameCtrl;
  late String _iconKey;
  late int _colorIndex;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editing?.name ?? '');
    _iconKey = widget.editing?.iconKey ?? kCategoryIconChoices.keys.first;
    _colorIndex = widget.editing?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool _isDuplicate(String name) {
    final lower = name.trim().toLowerCase();
    // Built-in keys + their localized labels + reserved keys.
    final builtIns = [
      ...(widget.income ? kDefaultIncomeCategories : kDefaultExpenseCategories),
      ...kReservedCategoryKeys,
    ];
    for (final b in builtIns) {
      if (b.toLowerCase() == lower) return true;
      if (context.categoryLabel(b).toLowerCase() == lower) return true;
    }
    for (final c in widget.existing.where((c) => c.isIncome == widget.income)) {
      if (c.id == widget.editing?.id) continue;
      if (c.name.toLowerCase() == lower) return true;
    }
    return false;
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = context.t('category.errorEmpty'));
      return;
    }
    if (_isDuplicate(name)) {
      setState(() => _error = context.t('category.errorDuplicate'));
      return;
    }
    final now = DateTime.now();
    final cat = _isEdit
        ? widget.editing!.copyWith(
            name: name, iconKey: _iconKey, colorIndex: _colorIndex, updatedAt: now)
        : CustomCategory(
            id: '',
            name: name,
            iconKey: _iconKey,
            colorIndex: _colorIndex,
            isIncome: widget.income,
            createdAt: now,
            updatedAt: now,
          );
    widget.onSaved(cat, _isEdit);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = customCategoryStyle(iconKey: _iconKey, colorIndex: _colorIndex);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: brand.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: brand.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Live preview
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                            color: style.background, shape: BoxShape.circle),
                        child: Icon(style.icon, size: 26, color: style.accent),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _nameCtrl.text.trim().isEmpty
                            ? context.t('category.newCategory')
                            : _nameCtrl.text.trim(),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: brand.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      hintText: context.t('category.nameHint'),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.expense, fontSize: 12)),
                ],
                const SizedBox(height: 18),
                _label(context.t('category.icon'), brand),
                const SizedBox(height: 10),
                // Fixed-height scrollable grid so the sheet stays compact, with
                // gradient fade edges like other scrollable areas.
                SizedBox(
                  height: 184,
                  child: FadingEdgeList(
                    fadeColor: brand.background,
                    topHeight: 14,
                    bottomHeight: 22,
                    child: GridView.count(
                      crossAxisCount: 6,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: kCategoryIconChoices.entries.map((e) {
                        final selected = e.key == _iconKey;
                        return GestureDetector(
                          onTap: () => setState(() => _iconKey = e.key),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected ? style.accent : brand.surface,
                              shape: BoxShape.circle,
                              border: selected
                                  ? null
                                  : Border.all(color: brand.divider),
                            ),
                            child: Icon(
                              e.value,
                              size: 20,
                              color: selected ? Colors.white : brand.inkSoft,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _label(context.t('category.color'), brand),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(kCategoryColorChoices.length, (i) {
                    final c = kCategoryColorChoices[i];
                    final selected = i == _colorIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _colorIndex = i),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: c.background,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? c.accent : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: selected
                            ? Icon(CupertinoIcons.checkmark_alt,
                                size: 18, color: c.accent)
                            : null,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(_isEdit
                        ? context.t('common.save')
                        : context.t('category.addCategory')),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, BrandColors brand) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: brand.inkSoft,
        ),
      );
}
