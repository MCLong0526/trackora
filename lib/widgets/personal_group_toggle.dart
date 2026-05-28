import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/i18n.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

class PersonalGroupToggle extends ConsumerStatefulWidget {
  final BrandColors brand;
  const PersonalGroupToggle({super.key, required this.brand});

  @override
  ConsumerState<PersonalGroupToggle> createState() =>
      _PersonalGroupToggleState();
}

class _PersonalGroupToggleState extends ConsumerState<PersonalGroupToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _barWidth = 200;
  double _fromLeft = 0;
  double _toLeft = 0;
  Curve _curve = Curves.easeOutBack;
  bool _initialized = false;
  bool _isDragging = false;
  int? _dragIndex;

  double get _pillW => _barWidth / 2;

  double _pillLeft(int idx) => idx * _pillW;

  double get _currentLeft {
    final t = _curve.transform(_ctrl.value.clamp(0.0, 1.0));
    return _fromLeft + (_toLeft - _fromLeft) * t;
  }

  void _animateToTab(int idx, {required bool fast}) {
    final target = _pillLeft(idx);
    _fromLeft = _currentLeft;
    _toLeft = target;
    _curve = fast ? Curves.easeOutCubic : Curves.easeOutBack;
    _ctrl.stop();
    _ctrl.duration = Duration(milliseconds: fast ? 150 : 320);
    _ctrl.value = 0;
    _ctrl.forward();
  }

  int _indexFromLocalX(double x) => x < _barWidth / 2 ? 0 : 1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(homeModeProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final hasGroup = groups.isNotEmpty;
    final memberCount = hasGroup ? groups.first.members.length : 0;
    final isPersonal = mode == HomeMode.personal;

    // Animate when mode changes from outside (tap elsewhere, not drag).
    ref.listen<HomeMode>(homeModeProvider, (_, next) {
      if (!_isDragging) {
        _animateToTab(next == HomeMode.personal ? 0 : 1, fast: false);
      }
    });

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          _barWidth = constraints.maxWidth;
          // One-time initialisation of pill position without triggering rebuild.
          if (!_initialized) {
            _fromLeft = _pillLeft(isPersonal ? 0 : 1);
            _toLeft = _fromLeft;
            _initialized = true;
          }
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (d) {
              final idx = _indexFromLocalX(d.localPosition.dx);
              HapticFeedback.mediumImpact();
              setState(() {
                _isDragging = true;
                _dragIndex = idx;
              });
              ref.read(homeModeProvider.notifier).state =
                  idx == 0 ? HomeMode.personal : HomeMode.group;
              _animateToTab(idx, fast: true);
            },
            onHorizontalDragUpdate: (d) {
              if (!_isDragging) return;
              final idx = _indexFromLocalX(d.localPosition.dx);
              if (idx == _dragIndex) return;
              HapticFeedback.selectionClick();
              setState(() => _dragIndex = idx);
              ref.read(homeModeProvider.notifier).state =
                  idx == 0 ? HomeMode.personal : HomeMode.group;
              _animateToTab(idx, fast: true);
            },
            onHorizontalDragEnd: (_) {
              if (!_isDragging) return;
              final cur = ref.read(homeModeProvider);
              setState(() {
                _isDragging = false;
                _dragIndex = null;
              });
              _animateToTab(cur == HomeMode.personal ? 0 : 1, fast: false);
            },
            onHorizontalDragCancel: () {
              if (!_isDragging) return;
              final cur = ref.read(homeModeProvider);
              setState(() {
                _isDragging = false;
                _dragIndex = null;
              });
              _animateToTab(cur == HomeMode.personal ? 0 : 1, fast: false);
            },
            child: Stack(
              clipBehavior: Clip.antiAlias,
              children: [
                // Sliding white pill — follows finger during drag, springs
                // back to final position on release.
                AnimatedBuilder(
                  animation: _ctrl,
                  builder: (context, _) => Positioned(
                    left: _currentLeft,
                    top: 0,
                    bottom: 0,
                    width: _pillW,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Tab labels row (sits on top of the pill).
                Row(
                  children: [
                    // Personal tab
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(homeModeProvider.notifier).state =
                              HomeMode.personal;
                        },
                        child: SizedBox(
                          height: double.infinity,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                color: isPersonal
                                    ? const Color(0xFF0B0B0F)
                                    : const Color(0xFF8E8E96),
                                fontSize: 14,
                                fontWeight: isPersonal
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              child: Text(context.t('group.personal')),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Group tab
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          ref.read(homeModeProvider.notifier).state =
                              HomeMode.group;
                        },
                        child: SizedBox(
                          height: double.infinity,
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hasGroup) ...[
                                  // Mini avatar stack
                                  SizedBox(
                                    width: memberCount > 1 ? 28 : 16,
                                    height: 20,
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          left: 0,
                                          child: Container(
                                            width: 16,
                                            height: 16,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEAE3F8),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (memberCount > 1)
                                          Positioned(
                                            left: 10,
                                            child: Container(
                                              width: 16,
                                              height: 16,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFD7F4E5),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Colors.white,
                                                  width: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: !isPersonal
                                        ? const Color(0xFF0B0B0F)
                                        : const Color(0xFF8E8E96),
                                    fontSize: 14,
                                    fontWeight: !isPersonal
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  child: Text(context.t('group.group')),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
