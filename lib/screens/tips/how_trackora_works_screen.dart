import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';

// ── Data model ─────────────────────────────────────────────────────────────────

class _TipStep {
  final IconData icon;
  final String title;
  final String description;

  const _TipStep({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _Topic {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<_TipStep> steps;

  const _Topic({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.steps,
  });
}

// ── Topic definitions ──────────────────────────────────────────────────────────

const List<_Topic> _kTopics = [
  _Topic(
    title: 'Add a Record in Seconds',
    subtitle: 'Track any expense, income or transfer instantly',
    icon: CupertinoIcons.bolt_fill,
    color: Color(0xFF6C63FF),
    steps: [
      _TipStep(
        icon: CupertinoIcons.plus_circle_fill,
        title: 'Tap the + Button',
        description:
            'The purple + button at the bottom of your screen opens the quick-add speed dial. Tap it any time to start a new record.',
      ),
      _TipStep(
        icon: CupertinoIcons.arrow_up_arrow_down_circle_fill,
        title: 'Choose Your Record Type',
        description:
            'Pick from Expense, Income, Transfer, or Receive. Each type has its own button in the speed dial that fans out.',
      ),
      _TipStep(
        icon: CupertinoIcons.number,
        title: 'Enter Amount with Smart Numpad',
        description:
            'Use the smart numpad to type your amount. It supports + − × ÷ so you can calculate a split without leaving the screen.',
      ),
      _TipStep(
        icon: CupertinoIcons.checkmark_circle_fill,
        title: 'Pick Category & Save',
        description:
            'Select a category, optionally add a note or snap a receipt, then tap Save. The record appears on your dashboard instantly.',
      ),
    ],
  ),

  _Topic(
    title: 'Double-Tap the Back of Your Phone',
    subtitle: 'Open Quick Add without unlocking your screen',
    icon: CupertinoIcons.hand_point_right_fill,
    color: Color(0xFFFF6B6B),
    steps: [
      _TipStep(
        icon: CupertinoIcons.settings,
        title: 'Open iPhone Settings',
        description:
            'On your iPhone, open the Settings app and go to Accessibility → Touch. This is where Back Tap is configured.',
      ),
      _TipStep(
        icon: CupertinoIcons.hand_point_right_fill,
        title: 'Scroll Down to Back Tap',
        description:
            'At the bottom of the Touch screen you\'ll find "Back Tap". Tap it to reveal the Double Tap and Triple Tap options.',
      ),
      _TipStep(
        icon: CupertinoIcons.app_fill,
        title: 'Set Double Tap → Trackora',
        description:
            'Tap "Double Tap", scroll down to App Shortcuts, and select Trackora. This links your back-tap gesture to Quick Add.',
      ),
      _TipStep(
        icon: CupertinoIcons.bolt_fill,
        title: 'Double-Tap to Add Instantly',
        description:
            'Now double-tap the back of your iPhone any time — even from the lock screen — and Quick Add opens immediately.',
      ),
    ],
  ),

  _Topic(
    title: 'Customize Your Manage Page',
    subtitle: 'Show only the features you actually use',
    icon: CupertinoIcons.slider_horizontal_3,
    color: Color(0xFF34C759),
    steps: [
      _TipStep(
        icon: CupertinoIcons.chart_bar_alt_fill,
        title: 'Go to the Budget Tab',
        description:
            'Tap the Budget tab (second from the right in the bottom nav). The Manage section lists all your financial tools.',
      ),
      _TipStep(
        icon: CupertinoIcons.pencil_circle_fill,
        title: 'Tap the Customize Button',
        description:
            'Look for the edit / customize icon at the top of the Manage section. Tap it to open the module visibility sheet.',
      ),
      _TipStep(
        icon: CupertinoIcons.power,
        title: 'Toggle Modules On or Off',
        description:
            'Each module (Installments, Savings, Travel Groups, etc.) has a toggle. Turn off features you don\'t use to keep things clean.',
      ),
      _TipStep(
        icon: CupertinoIcons.sparkles,
        title: 'Your Manage Page Updates',
        description:
            'Hidden modules disappear from the Manage page immediately. You can always come back here to re-enable them.',
      ),
    ],
  ),

  _Topic(
    title: 'Match Your Salary Cycle',
    subtitle: 'Reports that reset on your actual pay day',
    icon: CupertinoIcons.calendar_badge_plus,
    color: Color(0xFFFF9F0A),
    steps: [
      _TipStep(
        icon: CupertinoIcons.chart_bar_alt_fill,
        title: 'Go to the Budget Tab',
        description:
            'Tap the Budget tab. The Expense Cycle option is available in the Manage section — look for the cycle settings icon.',
      ),
      _TipStep(
        icon: CupertinoIcons.calendar,
        title: 'Open Expense Cycle',
        description:
            'Tap the cycle icon to open the Expense Cycle sheet. Here you can switch between calendar month and a custom start day.',
      ),
      _TipStep(
        icon: CupertinoIcons.checkmark_circle_fill,
        title: 'Enable & Set Your Salary Day',
        description:
            'Toggle "Custom Cycle" on, then pick the day of the month your salary arrives — e.g. the 15th or 25th.',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_bar_fill,
        title: 'All Reports Align to Your Pay Day',
        description:
            'Your Dashboard totals, Budget, and Statistics now reset from your pay day — not the 1st of the calendar month.',
      ),
    ],
  ),

  _Topic(
    title: 'Split Bills & Generate Receipt',
    subtitle: 'Divide shared costs and share a clean receipt image',
    icon: CupertinoIcons.person_2_fill,
    color: Color(0xFF007AFF),
    steps: [
      _TipStep(
        icon: CupertinoIcons.doc_text_fill,
        title: 'Open an Expense Form',
        description:
            'Add a new expense or edit an existing one. Scroll down on the form — you\'ll see a "Split Bill" section near the bottom.',
      ),
      _TipStep(
        icon: CupertinoIcons.person_badge_plus_fill,
        title: 'Add People to the Split',
        description:
            'Tap "+ Add Person" to pick from your contacts or People list. Enter each person\'s share amount — the remaining balance updates live.',
      ),
      _TipStep(
        icon: CupertinoIcons.equal_circle_fill,
        title: 'Confirm the Split',
        description:
            'Once the remaining balance reaches zero the split is complete. Adjust any amounts until everything balances out.',
      ),
      _TipStep(
        icon: CupertinoIcons.share_solid,
        title: 'Generate & Share Receipt',
        description:
            'Tap "Generate Receipt" to create a shareable image showing who owes what. Send it via WhatsApp or any other app.',
      ),
    ],
  ),

  _Topic(
    title: 'Travel Groups with Invite Code',
    subtitle: 'Track shared trip expenses with friends and family',
    icon: CupertinoIcons.airplane,
    color: Color(0xFFBF5AF2),
    steps: [
      _TipStep(
        icon: CupertinoIcons.square_stack_3d_up_fill,
        title: 'Go to Assets → Travel Groups',
        description:
            'Tap the Assets tab (rightmost in bottom nav), then open Travel Groups. Tap + to create a new trip.',
      ),
      _TipStep(
        icon: CupertinoIcons.qrcode,
        title: 'Share the Invite Code',
        description:
            'Your trip gets a unique invite code automatically. Share it with your travel companions via message or QR code.',
      ),
      _TipStep(
        icon: CupertinoIcons.person_2_fill,
        title: 'Friends Join with the Code',
        description:
            'Your travel companions create or open a Travel Group, tap "Join", and enter your invite code. They\'re instantly added.',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_pie_fill,
        title: 'Everyone Records & Splits',
        description:
            'Any group member can add expenses. Trackora calculates the total per person and suggests settlements automatically.',
      ),
    ],
  ),

  _Topic(
    title: 'Group Expense for Partners',
    subtitle: 'Track shared household spending together',
    icon: CupertinoIcons.heart_fill,
    color: Color(0xFFFF375F),
    steps: [
      _TipStep(
        icon: CupertinoIcons.arrow_2_squarepath,
        title: 'Switch to Group Mode',
        description:
            'On the Dashboard, tap the "Personal / Group" toggle at the top of the screen to switch to your shared group view.',
      ),
      _TipStep(
        icon: CupertinoIcons.person_2_fill,
        title: 'Create or Join a Group',
        description:
            'Create a new expense group for your household, then invite your partner by sharing the group ID. They join in seconds.',
      ),
      _TipStep(
        icon: CupertinoIcons.plus_circle_fill,
        title: 'Add Shared Expenses',
        description:
            'In Group mode, the + button adds expenses visible to all group members. Everyone can add, view, and manage records.',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_bar_fill,
        title: 'Track Combined Spending',
        description:
            'Your group Dashboard shows combined totals, budgets, and category breakdowns — perfect for managing finances together.',
      ),
    ],
  ),
];

// ── Main screen ────────────────────────────────────────────────────────────────

class HowTrackoraWorksScreen extends StatelessWidget {
  const HowTrackoraWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            pinned: true,
            backgroundColor: brand.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: Icon(CupertinoIcons.back, color: brand.ink, size: 22),
            ),
            title: Text(
              'How Trackora Works',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
          ),

          // Subtitle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'Tap a topic to see step-by-step instructions.',
                style: TextStyle(fontSize: 14, color: brand.inkSoft),
              ),
            ),
          ),

          // Topic list
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TopicCard(topic: _kTopics[i]),
                ),
                childCount: _kTopics.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Topic card ─────────────────────────────────────────────────────────────────

class _TopicCard extends StatefulWidget {
  final _Topic topic;
  const _TopicCard({required this.topic});

  @override
  State<_TopicCard> createState() => _TopicCardState();
}

class _TopicCardState extends State<_TopicCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 100),
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.97)
      .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final t = widget.topic;
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) {
          HapticFeedback.selectionClick();
          _ctrl.forward();
        },
        onTapUp: (_) {
          _ctrl.reverse();
          // Capture navigator before async gap.
          final nav = Navigator.of(context);
          Future.delayed(const Duration(milliseconds: 60), () {
            if (!mounted) return;
            nav.push(CupertinoPageRoute(
              builder: (_) => _TopicDetailScreen(topic: t),
            ));
          });
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                // Icon circle
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: t.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(t.icon, color: t.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: brand.inkSoft,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
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
  late final PageController _pageCtrl = PageController();
  int _current = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _go(int delta) {
    HapticFeedback.selectionClick();
    final next = _current + delta;
    if (next < 0 || next >= widget.topic.steps.length) {
      if (delta > 0) Navigator.pop(context);
      return;
    }
    _pageCtrl.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final steps = widget.topic.steps;
    final color = widget.topic.color;
    final isLast = _current == steps.length - 1;

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
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
                  // Step dots
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(steps.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeInOut,
                        width: i == _current ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: i == _current
                              ? color
                              : color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                  const Spacer(),
                  Text(
                    '${_current + 1}/${steps.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),

            // ── Page view ───────────────────────────────────────────
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
                  topicTitle: widget.topic.title,
                  color: color,
                ),
              ),
            ),

            // ── Navigation ──────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    if (_current > 0)
                      GestureDetector(
                        onTap: () => _go(-1),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: brand.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(
                            CupertinoIcons.chevron_left,
                            color: brand.ink,
                            size: 18,
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 52),

                    const SizedBox(width: 10),

                    Expanded(
                      child: GestureDetector(
                        onTap: () => _go(1),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              isLast ? 'Done' : 'Next',
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
  final String topicTitle;
  final Color color;

  const _StepPage({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.topicTitle,
    required this.color,
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
    final color = widget.color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),

          // Step badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Step ${widget.stepNumber} of ${widget.totalSteps}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Big illustration icon
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
            child: Icon(widget.step.icon, color: color, size: 42),
          ),

          const SizedBox(height: 20),

          // Step title
          Text(
            widget.step.title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: brand.ink,
              height: 1.2,
            ),
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            widget.step.description,
            style: TextStyle(
              fontSize: 15,
              color: brand.inkSoft,
              height: 1.6,
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}
