import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/amount_calc.dart';
import '../theme/app_theme.dart';

/// Adds calculator keys ( + − × ÷ = ) as a toolbar pinned directly above the
/// on-screen number pad, since the numeric keyboard itself has no operator
/// keys. Tapping a key inserts the operator at the cursor; `=` evaluates the
/// expression in place. The bar is shown via an [OverlayEntry] only while
/// [focusNode] has focus, and renders nothing inline.
class AmountOperatorBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const AmountOperatorBar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  State<AmountOperatorBar> createState() => _AmountOperatorBarState();
}

class _AmountOperatorBarState extends State<AmountOperatorBar> {
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    _removeBar();
    super.dispose();
  }

  void _onFocus() {
    if (widget.focusNode.hasFocus) {
      _showBar();
    } else {
      _removeBar();
    }
  }

  void _showBar() {
    if (_entry != null) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _buildBar);
    overlay.insert(_entry!);
  }

  void _removeBar() {
    _entry?.remove();
    _entry = null;
  }

  void _insert(String op) {
    HapticFeedback.selectionClick();
    final value = widget.controller.value;
    final text = value.text;
    final sel = value.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, op);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + op.length),
    );
    if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
  }

  void _equals() {
    HapticFeedback.selectionClick();
    final v = evalAmount(widget.controller.text);
    if (v == null || v < 0) return;
    final formatted = formatEvaluatedAmount(v);
    widget.controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  Widget _buildBar(BuildContext overlayContext) {
    // viewInsets.bottom is the keyboard height; pin the bar just above it.
    final inset = MediaQuery.of(overlayContext).viewInsets.bottom;
    if (inset <= 0) return const SizedBox.shrink();
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      left: 0,
      right: 0,
      bottom: inset,
      child: Material(
        color: isDark ? const Color(0xFF2A2A2C) : const Color(0xFFD9DCE1),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                _key('+', () => _insert('+'), brand),
                _key('−', () => _insert('-'), brand),
                _key('×', () => _insert('×'), brand),
                _key('÷', () => _insert('÷'), brand),
                _key('=', _equals, brand, accent: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _key(
    String label,
    VoidCallback onTap,
    BrandColors brand, {
    bool accent = false,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.5),
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent ? brand.accentDark : brand.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: accent ? Colors.white : brand.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
