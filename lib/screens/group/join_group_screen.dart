import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key});

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _codeCtrl = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final raw = _codeCtrl.text.trim().toUpperCase();
    if (raw.isEmpty) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _joining = true);
    try {
      final service = ref.read(expenseGroupServiceProvider);
      await service.joinGroup(
        rawCode: raw,
        userId: user.uid,
        displayName: user.email ?? 'Someone',
      );
      if (mounted) {
        AppToast.show(context, 'Joined group!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, context.t('group.invalidCode'));
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
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.xmark, color: AppActionBlue.color, size: 20),
        ),
        title: Text(
          context.t('group.joinGroup'),
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _codeCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'TRK·XXXX',
                    hintStyle: TextStyle(
                      color: brand.inkSoft,
                      fontSize: 20,
                      letterSpacing: 2,
                    ),
                    labelText: context.t('group.enterCode'),
                    labelStyle: TextStyle(
                      color: brand.inkSoft,
                      fontSize: 12,
                      letterSpacing: 0,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  onSubmitted: (_) => _join(),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: CupertinoButton.filled(
                  padding: EdgeInsets.zero,
                  onPressed: _joining ? null : _join,
                  child: _joining
                      ? const CupertinoActivityIndicator()
                      : Text(
                          context.t('group.joinGroup'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Ask a group member to share their invite code.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: brand.inkSoft,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
