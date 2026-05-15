import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/person.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_person_screen.dart';

const _avatarColors = [
  AppColors.lilac,
  AppColors.mint,
  AppColors.peach,
  AppColors.butter,
  AppColors.blush,
  AppColors.sky,
  AppColors.sage,
  AppColors.sand,
];

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _searchCtrl = TextEditingController();
  PersonType? _typeFilter;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Person> _filtered(List<Person> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return all.where((p) {
      if (q.isNotEmpty &&
          !p.name.toLowerCase().contains(q) &&
          !(p.phone?.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      if (_typeFilter != null && p.type != _typeFilter) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final async = ref.watch(peopleProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'People',
          style: TextStyle(
            color: brand.ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: () => _openAdd(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Search by name or phone…',
              onChanged: (_) => setState(() {}),
            ),
          ),
          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                  brand: brand,
                ),
                const SizedBox(width: 8),
                ...PersonType.values.map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: t.label,
                        selected: _typeFilter == t,
                        onTap: () => setState(
                          () => _typeFilter = _typeFilter == t ? null : t,
                        ),
                        brand: brand,
                      ),
                    )),
              ],
            ),
          ),
          // List
          Expanded(
            child: async.when(
              loading: () => const Center(child: CupertinoActivityIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                final list = _filtered(all);
                if (all.isEmpty) {
                  return _EmptyState(onAdd: () => _openAdd(context));
                }
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      'No results',
                      style: TextStyle(color: brand.inkSoft),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _PersonCard(
                    person: list[i],
                    userId: user?.uid,
                    onTap: () => _openEdit(context, list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openAdd(BuildContext context) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const AddEditPersonScreen()),
    );
  }

  void _openEdit(BuildContext context, Person p) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => AddEditPersonScreen(person: p)),
    );
  }
}

// ── Person card ───────────────────────────────────────────────────────────────

class _PersonCard extends ConsumerWidget {
  final Person person;
  final String? userId;
  final VoidCallback onTap;

  const _PersonCard({
    required this.person,
    required this.userId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final avatarBg = _avatarColors[person.colorIndex.clamp(0, _avatarColors.length - 1)];

    return Dismissible(
      key: ValueKey(person.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.expense,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(CupertinoIcons.delete, color: Colors.white, size: 22),
      ),
      confirmDismiss: (_) => _confirmDelete(context, ref),
      onDismissed: (_) async {
        if (userId == null) return;
        try {
          await ref.read(personServiceProvider).delete(userId!, person.id);
          if (context.mounted) {
            AppToast.show(context, 'Person removed', type: AppToastType.success);
          }
        } catch (_) {
          if (context.mounted) {
            AppToast.show(context, 'Failed to remove person', type: AppToastType.error);
          }
        }
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  person.initials,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _TypeBadge(person.type, brand),
                        if (person.phone != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            CupertinoIcons.phone,
                            size: 11,
                            color: brand.inkSoft,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            person.phone!,
                            style: TextStyle(
                              fontSize: 11,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (person.note != null && person.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        person.note!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: brand.inkSoft),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(CupertinoIcons.chevron_right, size: 16, color: brand.inkSoft),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context, WidgetRef ref) {
    return showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove Person?'),
        content: Text('Remove ${person.name} from your people list?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

// ── Type badge ────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final PersonType type;
  final BrandColors brand;
  const _TypeBadge(this.type, this.brand);

  @override
  Widget build(BuildContext context) {
    final (bg, icon) = switch (type) {
      PersonType.friend => (AppColors.lilac, CupertinoIcons.person_2_fill),
      PersonType.coworker => (AppColors.sky, CupertinoIcons.briefcase_fill),
      PersonType.family => (AppColors.mint, CupertinoIcons.house_fill),
      PersonType.other => (AppColors.sand, CupertinoIcons.ellipsis_circle_fill),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: brand.ink),
          const SizedBox(width: 3),
          Text(
            type.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter chip ───────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final BrandColors brand;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? brand.accentDark : brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: selected ? null : Border.all(color: brand.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? brand.background : brand.ink,
          ),
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.lilac,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                CupertinoIcons.person_2_fill,
                color: AppColors.ink,
                size: 30,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No people yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Save friends, family, and coworkers so you can quickly pick them when recording transfers.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: brand.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(CupertinoIcons.add, size: 16),
              label: const Text('Add Person'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact person picker widget for use in bottom sheets / form fields.
/// Returns a [Person] when one is tapped, or null if the user dismisses.
class PersonPickerSheet extends ConsumerStatefulWidget {
  final String? currentName;
  const PersonPickerSheet({super.key, this.currentName});

  @override
  ConsumerState<PersonPickerSheet> createState() => _PersonPickerSheetState();
}

class _PersonPickerSheetState extends ConsumerState<PersonPickerSheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final async = ref.watch(peopleProvider);

    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: brand.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Select Person',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const Spacer(),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: brand.inkSoft),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Search…',
              onChanged: (_) => setState(() {}),
            ),
          ),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CupertinoActivityIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e'),
            ),
            data: (all) {
              final q = _searchCtrl.text.trim().toLowerCase();
              final list = q.isEmpty
                  ? all
                  : all
                      .where((p) =>
                          p.name.toLowerCase().contains(q) ||
                          (p.phone?.toLowerCase().contains(q) ?? false))
                      .toList();
              if (list.isEmpty && all.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Column(
                    children: [
                      Text(
                        'No saved people yet.',
                        style: TextStyle(color: brand.inkSoft, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const AddEditPersonScreen(),
                            ),
                          );
                        },
                        icon: const Icon(CupertinoIcons.add, size: 14),
                        label: const Text('Add Person'),
                      ),
                    ],
                  ),
                );
              }
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Text(
                    'No results',
                    style: TextStyle(color: brand.inkSoft, fontSize: 13),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: list.length,
                  separatorBuilder: (ctx2, idx2) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final p = list[i];
                    final avatarBg = _avatarColors[
                        p.colorIndex.clamp(0, _avatarColors.length - 1)];
                    final isCurrent = widget.currentName == p.name;
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? brand.accentDark.withValues(alpha: 0.08)
                              : brand.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: isCurrent
                              ? Border.all(color: brand.accentDark, width: 1.5)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: avatarBg,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                p.initials,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: brand.ink,
                                    ),
                                  ),
                                  if (p.phone != null)
                                    Text(
                                      p.phone!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: brand.inkSoft,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            _TypeBadge(p.type, brand),
                            if (isCurrent) ...[
                              const SizedBox(width: 8),
                              Icon(
                                CupertinoIcons.checkmark_alt,
                                size: 16,
                                color: brand.accentDark,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
