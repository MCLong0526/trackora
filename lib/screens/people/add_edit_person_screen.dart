import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/person.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

/// Avatar background colors (indices 0–7) matching brand pastels.
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


class AddEditPersonScreen extends ConsumerStatefulWidget {
  final Person? person;
  const AddEditPersonScreen({super.key, this.person});

  @override
  ConsumerState<AddEditPersonScreen> createState() =>
      _AddEditPersonScreenState();
}

class _AddEditPersonScreenState extends ConsumerState<AddEditPersonScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  PersonType _type = PersonType.friend;
  int _colorIndex = 0;
  bool _saving = false;

  bool get _isEdit => widget.person != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.person!;
      _nameCtrl.text = p.name;
      _phoneCtrl.text = p.phone ?? '';
      _noteCtrl.text = p.note ?? '';
      _type = p.type;
      _colorIndex = p.colorIndex.clamp(0, _avatarColors.length - 1);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final person = Person(
        id: _isEdit ? widget.person!.id : DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameCtrl.text.trim(),
        type: _type,
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        colorIndex: _colorIndex,
        createdAt: _isEdit ? widget.person!.createdAt : now,
        updatedAt: now,
      );
      final svc = ref.read(personServiceProvider);
      if (_isEdit) {
        await svc.update(user.uid, person);
      } else {
        await svc.add(user.uid, person);
      }
      if (mounted) {
        AppToast.show(
          context,
          _isEdit ? 'Person updated' : 'Person added',
          type: AppToastType.success,
        );
        Navigator.pop(context, person);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed to save person', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final avatarBg = _avatarColors[_colorIndex];

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.xmark, color: brand.ink, size: 20),
        ),
        title: Text(
          _isEdit ? 'Edit Person' : 'Add Person',
          style: TextStyle(
            color: brand.ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CupertinoActivityIndicator()
                : Text(
                    'Save',
                    style: TextStyle(
                      color: brand.accentDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Avatar preview + color picker
            Center(
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: avatarBg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _nameCtrl.text.trim().isEmpty
                          ? '?'
                          : Person(
                              id: '',
                              name: _nameCtrl.text.trim(),
                              type: _type,
                              colorIndex: _colorIndex,
                              createdAt: DateTime.now(),
                              updatedAt: DateTime.now(),
                            ).initials,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Color swatches
                  Wrap(
                    spacing: 10,
                    children: List.generate(_avatarColors.length, (i) {
                      final selected = i == _colorIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _colorIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _avatarColors[i],
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: brand.ink, width: 2.5)
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Name
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Name *',
                hintText: 'e.g. Sarah, John',
                prefixIcon: Icon(CupertinoIcons.person),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),
            // Type chips
            _SectionLabel('Type', brand),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PersonType.values.map((t) {
                final selected = t == _type;
                return GestureDetector(
                  onTap: () => setState(() => _type = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? brand.accentDark : brand.surface,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: selected
                          ? null
                          : Border.all(color: brand.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _typeIcon(t),
                          size: 14,
                          color: selected ? brand.background : brand.inkSoft,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? brand.background : brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            // Phone (optional)
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone (optional)',
                hintText: 'e.g. +60123456789',
                prefixIcon: Icon(CupertinoIcons.phone),
              ),
            ),
            const SizedBox(height: 14),
            // Note (optional)
            TextFormField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Any notes about this person…',
                prefixIcon: Icon(CupertinoIcons.text_bubble),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(PersonType t) {
    switch (t) {
      case PersonType.friend:
        return CupertinoIcons.person_2_fill;
      case PersonType.coworker:
        return CupertinoIcons.briefcase_fill;
      case PersonType.family:
        return CupertinoIcons.house_fill;
      case PersonType.other:
        return CupertinoIcons.ellipsis_circle_fill;
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final BrandColors brand;
  const _SectionLabel(this.text, this.brand);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: brand.inkSoft,
        letterSpacing: 0.5,
      ),
    );
  }
}
