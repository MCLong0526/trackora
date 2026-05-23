import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'group_invite_screen.dart';
import 'join_group_screen.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  bool _creating = false;

  Future<void> _createInvite() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _creating = true);
    try {
      final service = ref.read(expenseGroupServiceProvider);
      final currency = await ref.read(prefsServiceProvider).currencyCode();
      final id = await service.createGroup(
        userId: user.uid,
        displayName: user.email?.split('@').first ?? 'You',
        groupName: 'Our Group',
        currency: currency,
      );
      ref.read(activeGroupIdProvider.notifier).state = id;
      // Find the newly created group
      final groups = ref.read(myGroupsProvider).valueOrNull ?? [];
      final group = groups.cast<dynamic>().firstWhere(
            (g) => g.id == id,
            orElse: () => null,
          );
      if (!mounted) return;
      if (group != null) {
        Navigator.pushReplacement(
          context,
          CupertinoPageRoute(builder: (_) => GroupInviteScreen(group: group)),
        );
      } else {
        // Group not yet in stream, push invite screen after short delay
        Navigator.pushReplacement(
          context,
          CupertinoPageRoute(builder: (_) => GroupInviteScreen(groupId: id)),
        );
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'Failed to create group');
    } finally {
      if (mounted) setState(() => _creating = false);
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
          'Group Expenses',
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Hero area
              SizedBox(
                width: 220,
                height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Lilac blob background
                    Positioned.fill(
                      child: Transform.rotate(
                        angle: -8 * (3.14159 / 180),
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAE3F8),
                            borderRadius: BorderRadius.circular(48),
                          ),
                        ),
                      ),
                    ),
                    // Two overlapping avatars
                    Positioned(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AvatarCircle(
                            letter: 'C',
                            bg: const Color(0xFFEAE3F8),
                            fg: const Color(0xFF5A4AAB),
                            size: 88,
                          ),
                          Transform.translate(
                            offset: const Offset(-22, 0),
                            child: _AvatarCircle(
                              letter: 'J',
                              bg: const Color(0xFFD7F4E5),
                              fg: const Color(0xFF1FBE71),
                              size: 88,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Floating receipt tile (top-right)
                    Positioned(
                      top: 12,
                      right: 8,
                      child: Transform.rotate(
                        angle: 8 * (3.14159 / 180),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.doc_text,
                            color: Color(0xFF1A6CFF),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                    // Floating heart tile (bottom-left)
                    Positioned(
                      bottom: 12,
                      left: 8,
                      child: Transform.rotate(
                        angle: -12 * (3.14159 / 180),
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            CupertinoIcons.heart_fill,
                            color: Color(0xFF1FBE71),
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Title
              Text(
                'Track expenses together',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Connect with one other person to share a group budget. Your personal expenses stay private.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF5B5B66),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // Feature pills card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FeaturePill(
                      dotColor: const Color(0xFF1FBE71),
                      text: 'Private invite — only one person can join',
                    ),
                    const SizedBox(height: 10),
                    _FeaturePill(
                      dotColor: const Color(0xFF1A6CFF),
                      text: 'Switch between Personal & Group any time',
                    ),
                    const SizedBox(height: 10),
                    _FeaturePill(
                      dotColor: const Color(0xFF9F8DDB),
                      text: 'Each expense shows who paid',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Create invite button
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  color: const Color(0xFF1A6CFF),
                  borderRadius: BorderRadius.circular(18),
                  onPressed: _creating ? null : _createInvite,
                  child: _creating
                      ? const CupertinoActivityIndicator(
                          color: Colors.white)
                      : const Text(
                          'Create invite',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Join instead ghost button
              CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute(builder: (_) => const JoinGroupScreen()),
                ),
                child: const Text(
                  'I have a code — join instead',
                  style: TextStyle(
                    color: Color(0xFF1A6CFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
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

class _AvatarCircle extends StatelessWidget {
  final String letter;
  final Color bg;
  final Color fg;
  final double size;

  const _AvatarCircle({
    required this.letter,
    required this.bg,
    required this.fg,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: fg,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  final Color dotColor;
  final String text;

  const _FeaturePill({required this.dotColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0B0B0F),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
