import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/expense_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class GroupInviteScreen extends ConsumerStatefulWidget {
  final ExpenseGroup? group;
  final String? groupId;

  const GroupInviteScreen({super.key, this.group, this.groupId})
      : assert(group != null || groupId != null,
            'Either group or groupId must be provided');

  @override
  ConsumerState<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends ConsumerState<GroupInviteScreen> {
  String? _rawCode;
  DateTime? _expiresAt;
  bool _loading = true;
  Timer? _timer;

  String get _effectiveGroupId => widget.group?.id ?? widget.groupId!;

  @override
  void initState() {
    super.initState();
    _generateCode();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _generateCode() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      final service = ref.read(expenseGroupServiceProvider);
      final raw = service.generateRawCode();
      await service.createInvite(
        rawCode: raw,
        groupId: _effectiveGroupId,
        createdBy: user.uid,
      );
      if (mounted) {
        setState(() {
          _rawCode = raw;
          _expiresAt = DateTime.now().add(const Duration(minutes: 10));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeRemaining() {
    if (_expiresAt == null) return '';
    final diff = _expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return context.t('group.inviteExpired');
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _expired =>
      _expiresAt != null && _expiresAt!.difference(DateTime.now()).isNegative;

  void _copyCode() {
    if (_rawCode == null) return;
    final display = '${_rawCode!.substring(0, 3)}·${_rawCode!.substring(3)}';
    Clipboard.setData(ClipboardData(text: display));
    AppToast.show(context, 'Code copied!');
  }

  void _shareMessages() {
    if (_rawCode == null) return;
    final display = '${_rawCode!.substring(0, 3)}·${_rawCode!.substring(3)}';
    Share.share(
      'Join my group on Trackora!\n\nInvite code: $display\n\nExpires in 10 minutes.',
    );
  }

  void _shareWhatsApp() {
    if (_rawCode == null) return;
    final display = '${_rawCode!.substring(0, 3)}·${_rawCode!.substring(3)}';
    Share.share(
      'Join my group on Trackora! Code: $display',
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final timeStr = _timeRemaining();

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
          'Invite a partner',
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CupertinoActivityIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Column(
                  children: [
                    // QR card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        children: [
                          // SCAN TO JOIN label
                          Text(
                            'SCAN TO JOIN',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: brand.inkSoft,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // QR code
                          if (_rawCode != null && !_expired) ...[
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(22),
                                  child: QrImageView(
                                    data: _rawCode!,
                                    version: QrVersions.auto,
                                    size: 210,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Colors.black,
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                                // Center logo
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A6CFF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'TK',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else if (_expired)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                context.t('group.inviteExpired'),
                                style: TextStyle(
                                  color: brand.inkSoft,
                                  fontSize: 15,
                                ),
                              ),
                            ),

                          const SizedBox(height: 20),

                          // OR ENTER CODE divider
                          Row(
                            children: [
                              Expanded(
                                  child: Divider(
                                      color: brand.divider, thickness: 0.5)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  'OR ENTER CODE',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: brand.inkSoft,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                              Expanded(
                                  child: Divider(
                                      color: brand.divider, thickness: 0.5)),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 6-char code boxes
                          if (_rawCode != null)
                            _CodeBoxes(rawCode: _rawCode!),

                          const SizedBox(height: 16),

                          // Expiry chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F4F7),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.lock_fill,
                                  size: 12,
                                  color: brand.inkSoft,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Private · expires in $timeStr',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: brand.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Share tiles row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ShareTile(
                          bg: const Color(0xFF25D366),
                          icon: CupertinoIcons.chat_bubble_fill,
                          label: 'WhatsApp',
                          onTap: _shareWhatsApp,
                        ),
                        _ShareTile(
                          bg: const Color(0xFF1A6CFF),
                          icon: CupertinoIcons.bubble_left_fill,
                          label: 'Messages',
                          onTap: _shareMessages,
                        ),
                        _ShareTile(
                          bg: const Color(0xFF1E1E24),
                          icon: CupertinoIcons.doc_on_doc_fill,
                          label: 'Copy code',
                          onTap: _expired ? null : _copyCode,
                        ),
                        _ShareTile(
                          bg: const Color(0xFF9F8DDB),
                          icon: CupertinoIcons.share_solid,
                          label: 'More',
                          onTap: _shareMessages,
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Cancel invite button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: brand.divider,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'Cancel invite',
                              style: TextStyle(
                                color: brand.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }
}

// ── Code boxes widget ────────────────────────────────────────────────────────

class _CodeBoxes extends StatelessWidget {
  final String rawCode;
  const _CodeBoxes({required this.rawCode});

  @override
  Widget build(BuildContext context) {
    final chars = rawCode.split('');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (int i = 0; i < 6; i++) ...[
          if (i == 3) ...[
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
          ],
          _CodeBox(char: i < chars.length ? chars[i] : ''),
          if (i < 5 && i != 2) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String char;
  const _CodeBox({required this.char});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          char,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: Color(0xFF0B0B0F),
          ),
        ),
      ),
    );
  }
}

// ── Share tile widget ────────────────────────────────────────────────────────

class _ShareTile extends StatelessWidget {
  final Color bg;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ShareTile({
    required this.bg,
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF5B5B66),
            ),
          ),
        ],
      ),
    );
  }
}
