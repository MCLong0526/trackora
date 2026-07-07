import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/person.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fading_edge_list.dart';
import '../../widgets/person_avatar.dart';
import 'add_edit_person_screen.dart';
import 'person_detail_screen.dart';

// Owed amounts read as a debt owed to the user — show them in the expense red
// so the People list matches the person-detail "Owes you" card.
const _kOwedColor = AppColors.expense;

// Localized label for a contact type (filter chips + person badge).
String _personTypeLabel(BuildContext context, PersonType t) =>
    context.t(switch (t) {
      PersonType.friend => 'people.typeFriend',
      PersonType.coworker => 'people.typeCoworker',
      PersonType.family => 'people.typeFamily',
      PersonType.other => 'people.typeOther',
    });

class _PeopleCoordinator extends ValueNotifier<String?> {
  _PeopleCoordinator() : super(null);
  void openRow(String id) => value = id;
  void closeAll() => value = null;
}

class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({super.key});

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  final _searchCtrl = TextEditingController();
  PersonType? _typeFilter;
  final _coordinator = _PeopleCoordinator();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _coordinator.dispose();
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
    final allBills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final currencySymbol =
        ref.watch(currencySymbolProvider).valueOrNull ?? 'RM';

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
          context.t('people.title'),
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
      body: GestureDetector(
        onTap: _coordinator.closeAll,
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: context.t('people.searchHint'),
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
                  label: context.t('people.filterAll'),
                  selected: _typeFilter == null,
                  onTap: () => setState(() => _typeFilter = null),
                  brand: brand,
                ),
                const SizedBox(width: 8),
                ...PersonType.values.map((t) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: _personTypeLabel(context, t),
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
            child: FadingEdgeList(
              fadeColor: brand.background,
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
                        context.t('people.noResults'),
                        style: TextStyle(color: brand.inkSoft),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    itemCount: list.length,
                    separatorBuilder: (ctx, idx) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final p = list[i];
                      final summary = personOwedSummary(
                        allBills,
                        p,
                        toBase: converter != null
                            ? (amt, from) => converter.toBase(amt, from)
                            : null,
                      );
                      return _PersonSwipeActions(
                        person: p,
                        userId: user?.uid,
                        coordinator: _coordinator,
                        onEdit: () => _openEdit(context, p),
                        child: _PersonCard(
                          person: p,
                          owedAmount:
                              summary.total > 0 ? summary.total : null,
                          currencySymbol: currencySymbol,
                          onTap: () => _openDetail(context, p),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
        ),
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

  void _openDetail(BuildContext context, Person p) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => PersonDetailScreen(person: p)),
    );
  }
}

// ── Person card ───────────────────────────────────────────────────────────────

class _PersonCard extends StatelessWidget {
  final Person person;
  final VoidCallback onTap;
  final double? owedAmount;
  final String currencySymbol;

  const _PersonCard({
    required this.person,
    required this.onTap,
    this.owedAmount,
    this.currencySymbol = 'RM',
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final owed = owedAmount;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            PersonAvatar(
              name: person.name,
              colorIndex: person.colorIndex,
              emoji: person.emoji,
              size: 48,
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
            if (owed != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    context.t('split.owesYou'),
                    style: TextStyle(
                      fontSize: 10,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '$currencySymbol ${owed.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kOwedColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
            ],
            Icon(CupertinoIcons.chevron_right, size: 16, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ── Swipe actions ─────────────────────────────────────────────────────────────

class _PersonSwipeActions extends ConsumerStatefulWidget {
  final Person person;
  final String? userId;
  final _PeopleCoordinator coordinator;
  final VoidCallback onEdit;
  final Widget child;

  const _PersonSwipeActions({
    required this.person,
    required this.userId,
    required this.coordinator,
    required this.onEdit,
    required this.child,
  });

  @override
  ConsumerState<_PersonSwipeActions> createState() =>
      _PersonSwipeActionsState();
}

class _PersonSwipeActionsState extends ConsumerState<_PersonSwipeActions>
    with SingleTickerProviderStateMixin {
  static const double _rightPanelW = 80.0;
  static const double _leftPanelW = 88.0;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  double _offset = 0;
  double _animStart = 0;
  double _animTarget = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.addListener(_onTick);
    widget.coordinator.addListener(_onCoordinatorChange);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordinatorChange);
    _ctrl.dispose();
    _curve.dispose();
    super.dispose();
  }

  void _onCoordinatorChange() {
    if (widget.coordinator.value != widget.person.id && _offset != 0) {
      _springAnimate(0);
    }
  }

  void _onTick() {
    setState(
      () => _offset = _animStart + (_animTarget - _animStart) * _curve.value,
    );
  }

  void _springAnimate(double target) {
    _ctrl.stop();
    _animStart = _offset;
    _animTarget = target;
    _ctrl
      ..reset()
      ..forward();
  }

  void _close() => _springAnimate(0);

  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    widget.coordinator.openRow(widget.person.id);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_rightPanelW, _leftPanelW);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_offset < 0) {
      (_offset < -_rightPanelW * 0.35 || v < -500)
          ? _springAnimate(-_rightPanelW)
          : _springAnimate(0);
    } else {
      (_offset > _leftPanelW * 0.35 || v > 500)
          ? _handleEditSwipe()
          : _springAnimate(0);
    }
  }

  Future<void> _handleEditSwipe() async {
    HapticFeedback.selectionClick();
    _springAnimate(_leftPanelW);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _springAnimate(0);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    widget.onEdit();
  }

  Future<void> _deletePerson() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('people.removeTitle')),
        content: Text('Remove ${widget.person.name} from your people list?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('people.remove')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await ref.read(personServiceProvider).delete(userId, widget.person.id);
        if (mounted) {
          AppToast.show(context, context.t('people.removed'),
              type: AppToastType.success);
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(context, context.t('people.removeFailed'),
              type: AppToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final revealRight = (-_offset / _rightPanelW).clamp(0.0, 1.0);
    final revealLeft = (_offset / _leftPanelW).clamp(0.0, 1.0);
    final isOpen = _offset != 0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // Right panel (swipe left): Delete
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _rightPanelW,
              child: _PSwipeAction(
                label: context.t('common.delete'),
                icon: CupertinoIcons.trash_fill,
                color: const Color.fromARGB(200, 255, 69, 58),
                reveal: revealRight,
                onTap: _deletePerson,
              ),
            ),
            // Left panel (swipe right): Edit
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _leftPanelW,
              child: _PSwipeAction(
                label: context.t('common.edit'),
                icon: CupertinoIcons.pencil,
                color: const Color.fromARGB(200, 0, 122, 255),
                reveal: revealLeft,
                onTap: _handleEditSwipe,
              ),
            ),
            // Main content
            Transform.translate(
              offset: Offset(_offset, 0),
              child: isOpen
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: AbsorbPointer(
                        child: Container(
                          color: brand.surface,
                          child: widget.child,
                        ),
                      ),
                    )
                  : Container(color: brand.surface, child: widget.child),
            ),
          ],
        ),
      ),
    );
  }
}

class _PSwipeAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double reveal;
  final VoidCallback onTap;

  const _PSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.reveal,
    required this.onTap,
  });

  @override
  State<_PSwipeAction> createState() => _PSwipeActionState();
}

class _PSwipeActionState extends State<_PSwipeAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: double.infinity,
        height: double.infinity,
        color: _pressed
            ? widget.color.withValues(alpha: widget.color.a * 0.72)
            : widget.color,
        child: Transform.scale(
          scale: 0.7 + 0.3 * widget.reveal,
          child: Opacity(
            opacity: widget.reveal.clamp(0.0, 1.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          Icon(icon, size: 10, color: foregroundOn(bg)),
          const SizedBox(width: 3),
          Text(
            _personTypeLabel(context, type),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: foregroundOn(bg),
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
              context.t('people.empty'),
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
              label: Text(context.t('people.addPerson')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Person picker that returns either a saved [Person] or a typed [String] name.
/// Returns [Person] if a saved contact is picked or saved, [String] for a
/// one-off name, or null if dismissed.
class PersonOrNamePickerSheet extends ConsumerStatefulWidget {
  final String? currentName;
  const PersonOrNamePickerSheet({super.key, this.currentName});

  @override
  ConsumerState<PersonOrNamePickerSheet> createState() =>
      _PersonOrNamePickerSheetState();
}

class _PersonOrNamePickerSheetState
    extends ConsumerState<PersonOrNamePickerSheet> {
  final _searchCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentName != null) _searchCtrl.text = widget.currentName!;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // New people are always saved to Contacts so they appear on the People page.
  Future<void> _addNew(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty || _saving) return;
    setState(() => _saving = true);
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null) {
      try {
        final now = DateTime.now();
        final person = Person(
          id: now.microsecondsSinceEpoch.toString(),
          name: name,
          type: PersonType.friend,
          colorIndex: personColorIndex(name),
          createdAt: now,
          updatedAt: now,
        );
        await ref.read(personServiceProvider).add(user.uid, person);
        if (mounted) Navigator.pop(context, person);
        return;
      } catch (_) {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    // Local mode without a signed-in user: fall back to a one-off name.
    if (mounted) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final async = ref.watch(peopleProvider);
    final query = _searchCtrl.text.trim();
    final queryLower = query.toLowerCase();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
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
                    context.t('people.selectPerson'),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                      letterSpacing: -0.374,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.t('common.cancel'),
                        style: TextStyle(color: brand.inkSoft)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CupertinoTextField(
                controller: _searchCtrl,
                placeholder: context.t('people.searchOrAdd'),
                autofocus: false,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                onSubmitted: _addNew,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Icon(CupertinoIcons.search,
                      size: 18, color: brand.inkSoft),
                ),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _body(brand, async, query, queryLower),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BrandColors brand,
    AsyncValue<List<Person>> async,
    String query,
    String queryLower,
  ) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: CupertinoActivityIndicator(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e'),
      ),
      data: (all) {
        final filtered = queryLower.isEmpty
            ? all
            : all
                .where((p) =>
                    p.name.toLowerCase().contains(queryLower) ||
                    (p.phone?.toLowerCase().contains(queryLower) ?? false))
                .toList();
        final exactExists =
            all.any((p) => p.name.toLowerCase() == queryLower);
        final showAddNew = query.isNotEmpty && !exactExists;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAddNew)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: GestureDetector(
                  onTap: _saving ? null : () => _addNew(query),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: brand.accentDark.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: brand.accentDark.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(CupertinoIcons.add,
                              size: 20, color: brand.accentDark),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${context.t('people.addToContacts')} "$query"',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: brand.accentDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_saving)
                          const CupertinoActivityIndicator()
                        else
                          Icon(CupertinoIcons.chevron_right,
                              size: 16, color: brand.accentDark),
                      ],
                    ),
                  ),
                ),
              ),
            if (filtered.isEmpty && !showAddNew)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  all.isEmpty
                      ? context.t('people.noContacts')
                      : context.t('people.noMatches'),
                  style: TextStyle(color: brand.inkSoft, fontSize: 13),
                ),
              )
            else if (filtered.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.38,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Row(
                          children: [
                            PersonAvatar(
                              name: p.name,
                              colorIndex: p.colorIndex,
                              emoji: p.emoji,
                              size: 40,
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
                                      fontWeight: FontWeight.w600,
                                      color: brand.ink,
                                    ),
                                  ),
                                  if (p.phone != null)
                                    Text(p.phone!,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: brand.inkSoft)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Legacy compact person picker (used by add_edit_expense_screen) ─────────────

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
                  context.t('people.selectPerson'),
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
                    context.t('common.cancel'),
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
              placeholder: context.t('people.searchShort'),
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
                        context.t('people.noSavedPeople'),
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
                        label: Text(context.t('people.addPerson')),
                      ),
                    ],
                  ),
                );
              }
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Text(
                    context.t('people.noResults'),
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
                            PersonAvatar(
                              name: p.name,
                              colorIndex: p.colorIndex,
                              emoji: p.emoji,
                              size: 40,
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
