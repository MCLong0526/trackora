import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  String? _error;
  String? _errorDetail;
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
    setState(() {
      _loading = true;
      _error = null;
      _errorDetail = null;
      _rawCode = null;
      _expiresAt = null;
    });
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.t('group.errorNotSignedIn');
        });
      }
      return;
    }
    try {
      // Verify the group exists on the server before issuing an invite.
      // A cache-only group (deleted server-side, or created offline and never
      // synced) cannot meaningfully be invited to.
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(_effectiveGroupId)
          .get(const GetOptions(source: Source.server));
      if (!groupDoc.exists) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = context.t('group.errorNotSynced');
          });
        }
        return;
      }

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
    } on FirebaseException catch (e) {
      if (mounted) {
        String message;
        switch (e.code) {
          case 'permission-denied':
            message = context.t('group.errorOnlineForCode');
            break;
          case 'unavailable':
          case 'deadline-exceeded':
            message = context.t('group.errorNetwork');
            break;
          case 'not-found':
            message = context.t('group.errorNotSynced');
            break;
          default:
            message = context.t('group.codeGenErrorRetry');
        }
        setState(() {
          _loading = false;
          _error = message;
          _errorDetail =
              kDebugMode ? '[${e.code}] ${e.message ?? ''}' : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.t('group.codeGenErrorRetry');
          _errorDetail = kDebugMode ? e.toString() : null;
        });
      }
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
    AppToast.show(context, context.t('group.codeCopied'));
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
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.chevron_back,
              color: brand.ink,
              size: 18,
            ),
          ),
        ),
        title: Text(
          context.t('group.invitePartnerTitle'),
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
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.wifi_slash,
                              size: 44, color: Color(0xFF8E8E96)),
                          const SizedBox(height: 16),
                          Text(
                            context.t('group.codeGenError'),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: context.brand.ink,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                                fontSize: 14,
                                color: context.brand.inkSoft),
                            textAlign: TextAlign.center,
                          ),
                          if (_errorDetail != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _errorDetail!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFB0B0B8),
                                fontFamily: 'monospace',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 24),
                          CupertinoButton.filled(
                            onPressed: _generateCode,
                            child: Text(context.t('group.tryAgain')),
                          ),
                        ],
                      ),
                    ),
                  )
                : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Column(
                  children: [
                    // QR card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Column(
                        children: [
                          // SCAN TO JOIN label
                          Text(
                            context.t('group.scanToJoin'),
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
                                  context.t('group.orEnterCode'),
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
                              color: brand.surface,
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
                                  context
                                      .t('group.privateExpiresIn')
                                      .replaceAll('{time}', timeStr),
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

                    // Copy code button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _expired ? null : _copyCode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _expired
                                ? const Color(0xFFF4F4F7)
                                : const Color(0xFF1E1E24),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.doc_on_doc_fill,
                                size: 16,
                                color: _expired
                                    ? const Color(0xFF8E8E96)
                                    : Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                context.t('group.copyCode'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _expired
                                      ? const Color(0xFF8E8E96)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
                            color: brand.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: brand.divider,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              context.t('group.cancelInvite'),
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
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          char,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
            color: context.brand.ink,
          ),
        ),
      ),
    );
  }
}

