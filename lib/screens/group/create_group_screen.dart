import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final service = ref.read(expenseGroupServiceProvider);
      final id = await service.createGroup(
        userId: user.uid,
        displayName: user.email ?? 'You',
        groupName: name,
        currency: await ref.read(prefsServiceProvider).currencyCode(),
      );
      ref.read(activeGroupIdProvider.notifier).state = id;
      ref.read(homeModeProvider.notifier).state = HomeMode.group;
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) AppToast.show(context, 'Failed to create group');
    } finally {
      if (mounted) setState(() => _saving = false);
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
          context.t('group.createGroup'),
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.only(right: 16),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CupertinoActivityIndicator()
                : Text(
                    context.t('common.save'),
                    style: const TextStyle(
                      color: AppActionBlue.color,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            _SectionCard(
              brand: brand,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: brand.ink, fontSize: 16),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: context.t('group.groupNameHint'),
                    hintStyle: TextStyle(color: brand.inkSoft),
                    labelText: context.t('group.groupName'),
                    labelStyle: TextStyle(
                      color: brand.inkSoft,
                      fontSize: 12,
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: CupertinoButton.filled(
                padding: EdgeInsets.zero,
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : Text(
                        context.t('group.createGroup'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final BrandColors brand;
  final Widget child;

  const _SectionCard({required this.brand, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
