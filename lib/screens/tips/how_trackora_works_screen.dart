import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

// ── Data model ─────────────────────────────────────────────────────────────────

class _TipStep {
  final String title;
  final String description;
  final Widget illustration;

  const _TipStep({
    required this.title,
    required this.description,
    required this.illustration,
  });
}

class _Topic {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final List<_TipStep> steps;

  const _Topic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.steps,
  });
}

// ── Illustration helpers ───────────────────────────────────────────────────────

/// A mock phone-frame illustration used as the step image.
/// Shows a relevant icon or mini-scene inside a rounded phone shape.
class _PhoneFrame extends StatelessWidget {
  final Widget child;
  final Color bgColor;

  const _PhoneFrame({required this.child, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 200,
        height: 350,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(36),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.06),
              blurRadius: 1,
              offset: const Offset(0, -1),
            ),
          ],
          border: Border.all(
            color: const Color(0xFF3A3A3C),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: Column(
            children: [
              // Dynamic island
              const SizedBox(height: 12),
              Container(
                width: 72,
                height: 26,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              // Screen content
              Expanded(
                child: Container(
                  color: bgColor,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Builds the phone screen content for a given illustration.
Widget _screenContent({
  required IconData icon,
  required Color iconColor,
  required Color bgColor,
  required String label,
  String? sublabel,
  bool showFab = false,
  bool showTabBar = false,
  List<IconData>? chips,
}) {
  return Stack(
    children: [
      // Fake top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border(
              bottom: BorderSide(
                color: Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
              ),
              const Spacer(),
              Container(
                width: 56,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        ),
      ),
      // Center icon + label
      Padding(
        padding: const EdgeInsets.only(top: 44, bottom: 48),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconColor.withValues(alpha: 0.9),
                      iconColor.withValues(alpha: 0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              if (sublabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (chips != null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: chips.map((ic) {
                    return Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(ic, size: 16, color: iconColor),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      // Optional FAB
      if (showFab)
        Positioned(
          bottom: showTabBar ? 56 : 18,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF6C63FF),
                    const Color(0xFF8B5CF6),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.5),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                CupertinoIcons.plus,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ),
      // Optional tab bar
      if (showTabBar)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: bgColor,
              border: Border(
                top: BorderSide(
                  color: Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                CupertinoIcons.house_fill,
                CupertinoIcons.chart_bar_fill,
                CupertinoIcons.circle,
                CupertinoIcons.chart_pie_fill,
                CupertinoIcons.square_stack_fill,
              ]
                  .map((ic) => Icon(
                        ic,
                        size: 18,
                        color: ic == CupertinoIcons.house_fill
                            ? const Color(0xFF6C63FF)
                            : Colors.black.withValues(alpha: 0.3),
                      ))
                  .toList(),
            ),
          ),
        ),
    ],
  );
}

// ── Topic definitions ──────────────────────────────────────────────────────────

List<_Topic> _buildTopics() {
  const lightBg = Color(0xFFF2F2F7);

  return [
    // 1. Add record in seconds
    _Topic(
      title: 'Add a Record in Seconds',
      subtitle: 'Track any expense, income or transfer instantly',
      icon: CupertinoIcons.bolt_fill,
      gradient: [const Color(0xFF6C63FF), const Color(0xFF9C89FF)],
      steps: [
        _TipStep(
          title: 'Tap the + Button',
          description:
              'The purple + button at the bottom of your screen is always accessible. Tap it to open the quick-add speed dial.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.plus_circle_fill,
              iconColor: const Color(0xFF6C63FF),
              bgColor: lightBg,
              label: 'Tap "+"',
              sublabel: 'Bottom center of screen',
              showFab: true,
              showTabBar: true,
            ),
          ),
        ),
        _TipStep(
          title: 'Choose Record Type',
          description:
              'Pick from Expense, Income, Transfer, or Receive. Each type has its own icon in the speed dial that pops up.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.arrow_up_arrow_down_circle_fill,
              iconColor: const Color(0xFF34C759),
              bgColor: lightBg,
              label: 'Choose Type',
              sublabel: 'Expense · Income · Transfer',
              chips: [
                CupertinoIcons.arrow_down_circle_fill,
                CupertinoIcons.arrow_up_circle_fill,
                CupertinoIcons.arrow_right_arrow_left_circle_fill,
              ],
            ),
          ),
        ),
        _TipStep(
          title: 'Enter Amount',
          description:
              'Use the smart numpad to type your amount. It supports +, −, ×, ÷ so you can split on the fly without a calculator.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.number,
              iconColor: const Color(0xFF007AFF),
              bgColor: lightBg,
              label: 'Smart Numpad',
              sublabel: '+ − × ÷ built-in',
              chips: [
                CupertinoIcons.plus,
                CupertinoIcons.minus,
                CupertinoIcons.multiply,
                CupertinoIcons.divide,
              ],
            ),
          ),
        ),
        _TipStep(
          title: 'Pick Category & Save',
          description:
              'Select a category, add an optional note or receipt photo, then tap Save. The record appears instantly on your dashboard.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.checkmark_seal_fill,
              iconColor: const Color(0xFF34C759),
              bgColor: lightBg,
              label: 'Save Record',
              sublabel: 'Instant dashboard update',
            ),
          ),
        ),
      ],
    ),

    // 2. Double-tap back
    _Topic(
      title: 'Double-Tap the Back of Your Phone',
      subtitle: 'Open Quick Add without unlocking your screen',
      icon: CupertinoIcons.hand_point_right_fill,
      gradient: [const Color(0xFFFF6B6B), const Color(0xFFFF9A5C)],
      steps: [
        _TipStep(
          title: 'Open iPhone Settings',
          description:
              'On your iPhone, go to Settings → Accessibility → Touch. This is where Back Tap lives.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.settings,
              iconColor: const Color(0xFF636366),
              bgColor: lightBg,
              label: 'Settings',
              sublabel: 'Accessibility → Touch',
            ),
          ),
        ),
        _TipStep(
          title: 'Scroll Down to Back Tap',
          description:
              'At the bottom of the Touch settings you\'ll find "Back Tap". Tap it to see the Double Tap and Triple Tap options.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.hand_point_right_fill,
              iconColor: const Color(0xFF007AFF),
              bgColor: lightBg,
              label: 'Back Tap',
              sublabel: 'Scroll to bottom of Touch',
            ),
          ),
        ),
        _TipStep(
          title: 'Set Double Tap Action',
          description:
              'Tap "Double Tap" and scroll down to find Trackora under the App Shortcuts section. Select it.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.app_fill,
              iconColor: const Color(0xFF6C63FF),
              bgColor: lightBg,
              label: 'Select Trackora',
              sublabel: 'Under App Shortcuts',
            ),
          ),
        ),
        _TipStep(
          title: 'Double-Tap to Add',
          description:
              'Now just double-tap the back of your iPhone at any time — even from your lock screen — and Quick Add opens immediately.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.bolt_fill,
              iconColor: const Color(0xFFFF6B6B),
              bgColor: lightBg,
              label: 'Tap Tap → Quick Add',
              sublabel: 'Works from lock screen',
            ),
          ),
        ),
      ],
    ),

    // 3. Manage Modules
    _Topic(
      title: 'Disable Modules You Don\'t Need',
      subtitle: 'Keep your interface clean and focused',
      icon: CupertinoIcons.slider_horizontal_3,
      gradient: [const Color(0xFF34C759), const Color(0xFF30D158)],
      steps: [
        _TipStep(
          title: 'Go to Profile',
          description:
              'Tap the avatar icon in the top-right corner of your dashboard to open Profile & Settings.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.person_crop_circle_fill,
              iconColor: const Color(0xFF6C63FF),
              bgColor: lightBg,
              label: 'Profile',
              sublabel: 'Top-right avatar button',
            ),
          ),
        ),
        _TipStep(
          title: 'Open Manage Modules',
          description:
              'Scroll down in Settings to find "Manage Modules". Tap it to see every feature Trackora offers.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.square_grid_2x2_fill,
              iconColor: const Color(0xFF34C759),
              bgColor: lightBg,
              label: 'Manage Modules',
              sublabel: 'In Settings scroll',
            ),
          ),
        ),
        _TipStep(
          title: 'Toggle Off What You Don\'t Use',
          description:
              'Each module has a toggle. Turn off Installments, Travel Groups, Precious Metals, or any feature you don\'t need.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.power,
              iconColor: const Color(0xFF34C759),
              bgColor: lightBg,
              label: 'Toggle Modules',
              sublabel: 'On / Off per feature',
              chips: [
                CupertinoIcons.creditcard_fill,
                CupertinoIcons.airplane,
                CupertinoIcons.cube_box_fill,
                CupertinoIcons.chart_bar_alt_fill,
              ],
            ),
          ),
        ),
        _TipStep(
          title: 'Clean, Focused Home Screen',
          description:
              'Hidden modules disappear from your dashboard, bottom nav, and quick-add menu — giving you a distraction-free experience.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.sparkles,
              iconColor: const Color(0xFF34C759),
              bgColor: lightBg,
              label: 'Clean Dashboard',
              sublabel: 'Only what matters',
              showTabBar: true,
            ),
          ),
        ),
      ],
    ),

    // 4. Salary cycle
    _Topic(
      title: 'Match Your Salary Cycle',
      subtitle: 'Reports that align with your actual pay period',
      icon: CupertinoIcons.calendar_badge_plus,
      gradient: [const Color(0xFFFF9F0A), const Color(0xFFFFCC02)],
      steps: [
        _TipStep(
          title: 'Open Expense Cycle Settings',
          description:
              'Tap your avatar → Settings → Expense Cycle. This lets you define a custom start date for your spending period.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.calendar,
              iconColor: const Color(0xFFFF9F0A),
              bgColor: lightBg,
              label: 'Expense Cycle',
              sublabel: 'Settings → Expense Cycle',
            ),
          ),
        ),
        _TipStep(
          title: 'Enable Custom Cycle',
          description:
              'Toggle on "Use Custom Cycle". This unlocks the date picker so you can set your actual salary date.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.checkmark_circle_fill,
              iconColor: const Color(0xFFFF9F0A),
              bgColor: lightBg,
              label: 'Enable Custom Cycle',
              sublabel: 'Toggle it on',
            ),
          ),
        ),
        _TipStep(
          title: 'Set Your Salary Date',
          description:
              'Pick the day of the month your salary arrives — e.g. the 15th or 25th. Trackora will use this as the cycle start.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.calendar_today,
              iconColor: const Color(0xFFFFCC02),
              bgColor: lightBg,
              label: 'Pick Day: 15th',
              sublabel: '1 → 28 of every month',
            ),
          ),
        ),
        _TipStep(
          title: 'Reports Align with Pay Day',
          description:
              'Your Dashboard, Budget, and Statistics now show spending from your last salary date — not the 1st of the calendar month.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.chart_bar_fill,
              iconColor: const Color(0xFFFF9F0A),
              bgColor: lightBg,
              label: 'Pay-Period Reports',
              sublabel: 'Cycle: 15 Jun → 14 Jul',
            ),
          ),
        ),
      ],
    ),

    // 5. Split bill + generate receipt
    _Topic(
      title: 'Split Bills & Generate Receipt',
      subtitle: 'Divide shared expenses and share a clean receipt',
      icon: CupertinoIcons.person_2_fill,
      gradient: [const Color(0xFF5AC8FA), const Color(0xFF007AFF)],
      steps: [
        _TipStep(
          title: 'Add a New Expense',
          description:
              'Open any expense entry (or create one via the + button). Scroll down on the form to find the "Split Bill" section.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.doc_text_fill,
              iconColor: const Color(0xFF007AFF),
              bgColor: lightBg,
              label: 'Expense Form',
              sublabel: 'Scroll down to Split Bill',
            ),
          ),
        ),
        _TipStep(
          title: 'Add People to the Split',
          description:
              'Tap "+ Add Person" to pick from your contacts or People list. Enter each person\'s share amount.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.person_badge_plus_fill,
              iconColor: const Color(0xFF5AC8FA),
              bgColor: lightBg,
              label: 'Add People',
              sublabel: 'Enter each share',
              chips: [
                CupertinoIcons.person_fill,
                CupertinoIcons.person_fill,
                CupertinoIcons.person_fill,
              ],
            ),
          ),
        ),
        _TipStep(
          title: 'Review the Split',
          description:
              'Trackora shows each person\'s share and the remaining balance in real time. Adjust amounts until the split balances.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.equal_circle_fill,
              iconColor: const Color(0xFF5AC8FA),
              bgColor: lightBg,
              label: 'Balanced Split',
              sublabel: 'Remaining: RM 0.00',
            ),
          ),
        ),
        _TipStep(
          title: 'Generate & Share Receipt',
          description:
              'Tap "Generate Receipt" to create a beautiful shareable image showing who owes what. Send it via WhatsApp or any app.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.share_solid,
              iconColor: const Color(0xFF007AFF),
              bgColor: lightBg,
              label: 'Share Receipt',
              sublabel: 'Beautiful image summary',
            ),
          ),
        ),
      ],
    ),

    // 6. Travel groups
    _Topic(
      title: 'Travel Groups with Invite Code',
      subtitle: 'Track group trip expenses with friends and family',
      icon: CupertinoIcons.airplane,
      gradient: [const Color(0xFFBF5AF2), const Color(0xFFDA8FFF)],
      steps: [
        _TipStep(
          title: 'Create a Travel Group',
          description:
              'Go to Assets → Travel Groups, then tap the + button to create a new group. Give your trip a name and base currency.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.airplane,
              iconColor: const Color(0xFFBF5AF2),
              bgColor: lightBg,
              label: 'Create Trip',
              sublabel: 'Assets → Travel Groups → +',
            ),
          ),
        ),
        _TipStep(
          title: 'Share the Invite Code',
          description:
              'Trackora generates a unique 6-character invite code for your trip. Share it with friends via message or QR code.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.qrcode,
              iconColor: const Color(0xFFBF5AF2),
              bgColor: lightBg,
              label: 'Invite Code',
              sublabel: 'e.g. TRP-4X9K',
            ),
          ),
        ),
        _TipStep(
          title: 'Friends Join with the Code',
          description:
              'Your travel companions tap + → "Join Trip" and enter the 6-character code. They immediately see the shared trip.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.person_2_fill,
              iconColor: const Color(0xFFDA8FFF),
              bgColor: lightBg,
              label: 'Join Trip',
              sublabel: 'Enter invite code',
              chips: [
                CupertinoIcons.person_fill,
                CupertinoIcons.person_fill,
                CupertinoIcons.person_fill,
                CupertinoIcons.person_fill,
              ],
            ),
          ),
        ),
        _TipStep(
          title: 'Add Expenses & See Splits',
          description:
              'Anyone in the group can add expenses. Trackora automatically calculates who paid and who owes — with settlement suggestions.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.chart_pie_fill,
              iconColor: const Color(0xFFBF5AF2),
              bgColor: lightBg,
              label: 'Auto-Split',
              sublabel: 'Who owes whom',
            ),
          ),
        ),
      ],
    ),

    // 7. Group expense
    _Topic(
      title: 'Group Expense for Partners',
      subtitle: 'Track shared spending with your partner or household',
      icon: CupertinoIcons.heart_fill,
      gradient: [const Color(0xFFFF375F), const Color(0xFFFF6E6E)],
      steps: [
        _TipStep(
          title: 'Switch to Group Mode',
          description:
              'On the Dashboard, tap the "Personal / Group" toggle at the top. This switches between your personal view and shared group view.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.arrow_2_squarepath,
              iconColor: const Color(0xFFFF375F),
              bgColor: lightBg,
              label: 'Switch to Group',
              sublabel: 'Personal ↔ Group toggle',
            ),
          ),
        ),
        _TipStep(
          title: 'Create or Join a Group',
          description:
              'Create a new expense group for your household and invite your partner by sharing the group ID. They join in seconds.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.heart_circle_fill,
              iconColor: const Color(0xFFFF375F),
              bgColor: lightBg,
              label: 'Partner Group',
              sublabel: 'Create → Share ID',
            ),
          ),
        ),
        _TipStep(
          title: 'Add Shared Expenses',
          description:
              'In Group mode, the + button adds expenses visible to all group members. Each member can add, edit, and see all records.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.plus_circle_fill,
              iconColor: const Color(0xFFFF6E6E),
              bgColor: lightBg,
              label: 'Shared Expenses',
              sublabel: 'Everyone sees in real time',
              showFab: true,
              showTabBar: true,
            ),
          ),
        ),
        _TipStep(
          title: 'Track Combined Spending',
          description:
              'Your group\'s Dashboard shows combined totals, budgets, and category breakdowns — perfect for managing household finances together.',
          illustration: _PhoneFrame(
            bgColor: lightBg,
            child: _screenContent(
              icon: CupertinoIcons.chart_bar_fill,
              iconColor: const Color(0xFFFF375F),
              bgColor: lightBg,
              label: 'Combined Dashboard',
              sublabel: 'Budget · Stats · Summary',
            ),
          ),
        ),
      ],
    ),
  ];
}

// ── Main screen ────────────────────────────────────────────────────────────────

class HowTrackoraWorksScreen extends StatefulWidget {
  const HowTrackoraWorksScreen({super.key});

  @override
  State<HowTrackoraWorksScreen> createState() => _HowTrackoraWorksScreenState();
}

class _HowTrackoraWorksScreenState extends State<HowTrackoraWorksScreen> {
  late final List<_Topic> _topics = _buildTopics();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, brand),
          _buildTopicList(context, brand),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, BrandColors brand) {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: brand.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: () => Navigator.pop(context),
        child: Icon(
          CupertinoIcons.back,
          color: brand.ink,
          size: 22,
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How Trackora Works',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: brand.ink,
              ),
            ),
            Text(
              '${_topics.length} topics',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: brand.inkSoft,
              ),
            ),
          ],
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF6C63FF).withValues(alpha: 0.15),
                const Color(0xFF9C89FF).withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 60, right: 24),
              child: Icon(
                CupertinoIcons.lightbulb_fill,
                size: 64,
                color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopicList(BuildContext context, BrandColors brand) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _TopicCard(topic: _topics[i], index: i),
          ),
          childCount: _topics.length,
        ),
      ),
    );
  }
}

// ── Topic card ─────────────────────────────────────────────────────────────────

class _TopicCard extends StatefulWidget {
  final _Topic topic;
  final int index;

  const _TopicCard({required this.topic, required this.index});

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final topic = widget.topic;

    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          _ctrl.forward();
        },
        onTapUp: (_) {
          _ctrl.reverse();
          // Capture navigator before the async gap to satisfy the linter.
          final nav = Navigator.of(context);
          Future.delayed(const Duration(milliseconds: 60), () {
            if (!mounted) return;
            nav.push(
              CupertinoPageRoute(
                builder: (_) => _TopicDetailScreen(topic: topic),
              ),
            );
          });
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: topic.gradient,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: topic.gradient.first.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(topic.icon, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        topic.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        topic.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: brand.inkSoft,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  topic.gradient.first.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${topic.steps.length} steps',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: topic.gradient.first,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: brand.inkSoft,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Topic detail screen ────────────────────────────────────────────────────────

class _TopicDetailScreen extends StatefulWidget {
  final _Topic topic;

  const _TopicDetailScreen({required this.topic});

  @override
  State<_TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<_TopicDetailScreen> {
  late PageController _pageCtrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_current < widget.topic.steps.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    HapticFeedback.selectionClick();
    if (_current > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final steps = widget.topic.steps;
    final isLast = _current == steps.length - 1;

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: const EdgeInsets.all(8),
                    onPressed: () => Navigator.pop(context),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: brand.inkSoft,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  // Step indicator pills
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        width: i == _current ? 20 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _current
                              ? widget.topic.gradient.first
                              : widget.topic.gradient.first
                                  .withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_current + 1} / ${steps.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Topic chip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: widget.topic.gradient,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(widget.topic.icon,
                            color: Colors.white, size: 12),
                        const SizedBox(width: 5),
                        Text(
                          widget.topic.title,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: steps.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _current = i);
                },
                itemBuilder: (_, i) => _StepPage(
                  step: steps[i],
                  stepNumber: i + 1,
                  totalSteps: steps.length,
                  accentColor: widget.topic.gradient.first,
                ),
              ),
            ),

            // Navigation buttons
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Row(
                  children: [
                    // Prev button
                    if (_current > 0)
                      GestureDetector(
                        onTap: _prev,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: brand.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            CupertinoIcons.chevron_left,
                            color: brand.ink,
                            size: 20,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 54),

                    const SizedBox(width: 12),

                    // Next / Done button
                    Expanded(
                      child: GestureDetector(
                        onTap: _next,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          height: 54,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: widget.topic.gradient,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: widget.topic.gradient.first
                                    .withValues(alpha: 0.4),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              isLast ? 'Done' : 'Next Step',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step page ──────────────────────────────────────────────────────────────────

class _StepPage extends StatefulWidget {
  final _TipStep step;
  final int stepNumber;
  final int totalSteps;
  final Color accentColor;

  const _StepPage({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.accentColor,
  });

  @override
  State<_StepPage> createState() => _StepPageState();
}

class _StepPageState extends State<_StepPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final brand = context.brand;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step label
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Step ${widget.stepNumber}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Title
            Text(
              widget.step.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: brand.ink,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),

            // Description
            Text(
              widget.step.description,
              style: TextStyle(
                fontSize: 15,
                color: brand.inkSoft,
                height: 1.55,
              ),
            ),

            const SizedBox(height: 28),

            // Illustration
            SizedBox(
              height: 360,
              child: widget.step.illustration,
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
