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
  final ExpenseGroup group;

  const GroupInviteScreen({super.key, required this.group});

  @override
  ConsumerState<GroupInviteScreen> createState() => _GroupInviteScreenState();
}

class _GroupInviteScreenState extends ConsumerState<GroupInviteScreen>
    with SingleTickerProviderStateMixin {
  String? _rawCode;
  DateTime? _expiresAt;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generateCode();
    _startTimer();
  }

  void _startTimer() {
    // Rebuild every second to update countdown
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {});
      return true;
    });
  }

  Future<void> _generateCode() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      final service = ref.read(expenseGroupServiceProvider);
      final raw = service.generateRawCode();
      await service.createInvite(
        rawCode: raw,
        groupId: widget.group.id,
        createdBy: user.uid,
      );
      if (mounted) {
        setState(() {
          _rawCode = raw;
          _expiresAt = DateTime.now().add(const Duration(hours: 24));
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerate() async {
    setState(() => _loading = true);
    await _generateCode();
  }

  String _timeRemaining() {
    if (_expiresAt == null) return '';
    final diff = _expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return context.t('group.inviteExpired');
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _copyCode() {
    if (_rawCode == null) return;
    Clipboard.setData(ClipboardData(text: _rawCode!));
    AppToast.show(context, 'Code copied!');
  }

  void _shareCode() {
    if (_rawCode == null) return;
    Share.share(
      'Join my group "${widget.group.name}" on Trackora!\n\nInvite code: $_rawCode\n\nExpires in 24 hours.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final timeStr = _timeRemaining();
    final expired = _expiresAt != null &&
        _expiresAt!.difference(DateTime.now()).isNegative;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.chevron_back, color: AppActionBlue.color, size: 20),
        ),
        title: Text(
          context.t('group.inviteMembers'),
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
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // QR Code card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        if (_rawCode != null && !expired) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: QrImageView(
                              data: _rawCode!,
                              version: QrVersions.auto,
                              size: 180,
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ] else if (expired)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              context.t('group.inviteExpired'),
                              style: TextStyle(
                                color: brand.inkSoft,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        // Code display
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            color: brand.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _rawCode ?? '—',
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Expiry
                        if (!expired && timeStr.isNotEmpty)
                          Text(
                            context.t('group.inviteExpiry').replaceAll('{time}', timeStr),
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          context.t('group.singleUse'),
                          style: TextStyle(
                            color: brand.inkSoft,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          brand: brand,
                          icon: CupertinoIcons.doc_on_doc,
                          label: context.t('group.copyCode'),
                          onTap: expired ? null : _copyCode,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionButton(
                          brand: brand,
                          icon: CupertinoIcons.share,
                          label: context.t('group.shareCode'),
                          onTap: expired ? null : _shareCode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ActionButton(
                    brand: brand,
                    icon: CupertinoIcons.refresh,
                    label: context.t('group.newCode'),
                    onTap: _regenerate,
                    fullWidth: true,
                  ),

                  const SizedBox(height: 24),
                  // Join instructions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.info_circle,
                            color: AppActionBlue.color, size: 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Ask friends to scan the QR code or enter the invite code in Trackora → Groups → Join Group.',
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final BrandColors brand;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;

  const _ActionButton({
    required this.brand,
    required this.icon,
    required this.label,
    this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: 14,
          horizontal: fullWidth ? 0 : 0,
        ),
        decoration: BoxDecoration(
          color: disabled
              ? brand.surface.withValues(alpha: 0.5)
              : brand.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: brand.divider.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color:
                    disabled ? brand.inkSoft : AppActionBlue.color,
                size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: disabled
                    ? brand.inkSoft
                    : AppActionBlue.color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
