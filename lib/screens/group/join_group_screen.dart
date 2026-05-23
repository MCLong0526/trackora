import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'qr_scanner_screen.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _focusNode = FocusNode();
  final _hiddenController = TextEditingController();
  String _entered = '';
  bool _joining = false;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _hiddenController.addListener(_onTextChanged);
    // Blinking cursor
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 530));
      if (!mounted) return false;
      setState(() => _cursorVisible = !_cursorVisible);
      return true;
    });
    // Auto-focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hiddenController.removeListener(_onTextChanged);
    _hiddenController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _hiddenController.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final limited = text.length > 6 ? text.substring(0, 6) : text;
    if (limited != _entered) {
      setState(() => _entered = limited);
      // Sync the controller
      if (_hiddenController.text != limited) {
        _hiddenController.value = TextEditingValue(
          text: limited,
          selection: TextSelection.collapsed(offset: limited.length),
        );
      }
      if (limited.length == 6) {
        _join();
      }
    }
  }

  Future<void> _scanQR() async {
    final code = await Navigator.push<String>(
      context,
      CupertinoPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (code != null && code.length == 6 && mounted) {
      setState(() {
        _entered = code;
        _hiddenController.value = TextEditingValue(
          text: code,
          selection: TextSelection.collapsed(offset: code.length),
        );
      });
      _join();
    }
  }

  Future<void> _join() async {
    final raw = _entered;
    if (raw.length != 6) {
      AppToast.show(context, 'Please enter the full 6-character code');
      return;
    }

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _joining = true);
    try {
      final service = ref.read(expenseGroupServiceProvider);
      await service.joinGroup(
        rawCode: raw,
        userId: user.uid,
        displayName: user.email?.split('@').first ?? 'Someone',
      );
      if (mounted) {
        ref.read(homeModeProvider.notifier).state = HomeMode.group;
        AppToast.show(context, 'Joined group!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, context.t('group.invalidCode'));
        setState(() {
          _entered = '';
          _hiddenController.clear();
          _joining = false;
        });
      }
    } finally {
      if (mounted) setState(() => _joining = false);
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
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.chevron_back,
              color: Color(0xFF0B0B0F),
              size: 18,
            ),
          ),
        ),
        title: Text(
          'Join group',
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      'Enter the invite code',
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Ask your partner to open Group Expenses and share their 6-character code.',
                      style: TextStyle(
                        color: const Color(0xFF5B5B66),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // 6 individual code boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < 6; i++) ...[
                          if (i == 3)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '·',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8E8E96),
                                ),
                              ),
                            ),
                          _InputBox(
                            char: i < _entered.length
                                ? _entered[i]
                                : null,
                            isActive: i == _entered.length && !_joining,
                            cursorVisible: _cursorVisible,
                          ),
                          if (i < 5 && i != 2) const SizedBox(width: 6),
                        ],
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Scan QR card
                    GestureDetector(
                      onTap: _scanQR,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A6CFF)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                CupertinoIcons.qrcode,
                                color: Color(0xFF1A6CFF),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Scan QR instead',
                                    style: TextStyle(
                                      color: brand.ink,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Use your camera to scan their code',
                                    style: TextStyle(
                                      color: brand.inkSoft,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              color: brand.inkSoft,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Lock note
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.lock_fill,
                          size: 12,
                          color: brand.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Codes are private & expire in 10 minutes',
                          style: TextStyle(
                            color: brand.inkSoft,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Hidden text field to capture input
                Positioned(
                  left: 0,
                  top: 0,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: TextField(
                      controller: _hiddenController,
                      focusNode: _focusNode,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      cursorColor: Colors.transparent,
                      cursorWidth: 0,
                    ),
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

class _InputBox extends StatelessWidget {
  final String? char;
  final bool isActive;
  final bool cursorVisible;

  const _InputBox({
    required this.char,
    required this.isActive,
    required this.cursorVisible,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color? borderColor;
    double borderWidth = 0;

    if (char != null) {
      // Filled
      bgColor = Colors.white;
    } else if (isActive) {
      // Active/current
      bgColor = Colors.white;
      borderColor = const Color(0xFF1A6CFF);
      borderWidth = 2;
    } else {
      // Empty/inactive
      bgColor = const Color(0xFFF4F4F7);
    }

    return Container(
      width: 46,
      height: 58,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: borderColor != null
            ? Border.all(color: borderColor, width: borderWidth)
            : null,
        boxShadow: char != null
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (char != null)
            Text(
              char!,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                color: Color(0xFF0B0B0F),
              ),
            )
          else if (isActive && cursorVisible)
            Container(
              width: 2,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1A6CFF),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}
