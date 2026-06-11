import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/i18n.dart';
import '../../theme/app_theme.dart';

// ── Data model ─────────────────────────────────────────────────────────────────
//
// Topics and steps store i18n *keys* (not literal text) so the whole screen can
// stay `const` while still rendering in the active language via `context.t()`.

class _TipStep {
  final IconData icon;
  final String titleKey;
  final String bodyKey;

  const _TipStep({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });
}

class _Topic {
  final String titleKey;
  final String subtitleKey;
  final IconData icon;
  final Color color;
  final List<_TipStep> steps;

  const _Topic({
    required this.titleKey,
    required this.subtitleKey,
    required this.icon,
    required this.color,
    required this.steps,
  });
}

// ── Topic definitions ──────────────────────────────────────────────────────────

const List<_Topic> _kTopics = [
  _Topic(
    titleKey: 'tips.add.title',
    subtitleKey: 'tips.add.sub',
    icon: CupertinoIcons.bolt_fill,
    color: Color(0xFF6C63FF),
    steps: [
      _TipStep(
        icon: CupertinoIcons.plus_circle_fill,
        titleKey: 'tips.add.s1t',
        bodyKey: 'tips.add.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.arrow_up_arrow_down_circle_fill,
        titleKey: 'tips.add.s2t',
        bodyKey: 'tips.add.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.number,
        titleKey: 'tips.add.s3t',
        bodyKey: 'tips.add.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.checkmark_circle_fill,
        titleKey: 'tips.add.s4t',
        bodyKey: 'tips.add.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.backTap.title',
    subtitleKey: 'tips.backTap.sub',
    icon: CupertinoIcons.hand_point_right_fill,
    color: Color(0xFFFF6B6B),
    steps: [
      _TipStep(
        icon: CupertinoIcons.settings,
        titleKey: 'tips.backTap.s1t',
        bodyKey: 'tips.backTap.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.hand_point_right_fill,
        titleKey: 'tips.backTap.s2t',
        bodyKey: 'tips.backTap.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.app_fill,
        titleKey: 'tips.backTap.s3t',
        bodyKey: 'tips.backTap.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.bolt_fill,
        titleKey: 'tips.backTap.s4t',
        bodyKey: 'tips.backTap.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.customize.title',
    subtitleKey: 'tips.customize.sub',
    icon: CupertinoIcons.slider_horizontal_3,
    color: Color(0xFF34C759),
    steps: [
      _TipStep(
        icon: CupertinoIcons.chart_bar_alt_fill,
        titleKey: 'tips.customize.s1t',
        bodyKey: 'tips.customize.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.pencil_circle_fill,
        titleKey: 'tips.customize.s2t',
        bodyKey: 'tips.customize.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.power,
        titleKey: 'tips.customize.s3t',
        bodyKey: 'tips.customize.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.sparkles,
        titleKey: 'tips.customize.s4t',
        bodyKey: 'tips.customize.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.cycle.title',
    subtitleKey: 'tips.cycle.sub',
    icon: CupertinoIcons.calendar_badge_plus,
    color: Color(0xFFFF9F0A),
    steps: [
      _TipStep(
        icon: CupertinoIcons.chart_bar_alt_fill,
        titleKey: 'tips.cycle.s1t',
        bodyKey: 'tips.cycle.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.calendar,
        titleKey: 'tips.cycle.s2t',
        bodyKey: 'tips.cycle.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.checkmark_circle_fill,
        titleKey: 'tips.cycle.s3t',
        bodyKey: 'tips.cycle.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_bar_fill,
        titleKey: 'tips.cycle.s4t',
        bodyKey: 'tips.cycle.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.split.title',
    subtitleKey: 'tips.split.sub',
    icon: CupertinoIcons.person_2_fill,
    color: Color(0xFF007AFF),
    steps: [
      _TipStep(
        icon: CupertinoIcons.doc_text_fill,
        titleKey: 'tips.split.s1t',
        bodyKey: 'tips.split.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.person_badge_plus_fill,
        titleKey: 'tips.split.s2t',
        bodyKey: 'tips.split.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.equal_circle_fill,
        titleKey: 'tips.split.s3t',
        bodyKey: 'tips.split.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.share_solid,
        titleKey: 'tips.split.s4t',
        bodyKey: 'tips.split.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.travel.title',
    subtitleKey: 'tips.travel.sub',
    icon: CupertinoIcons.airplane,
    color: Color(0xFFBF5AF2),
    steps: [
      _TipStep(
        icon: CupertinoIcons.square_stack_3d_up_fill,
        titleKey: 'tips.travel.s1t',
        bodyKey: 'tips.travel.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.qrcode,
        titleKey: 'tips.travel.s2t',
        bodyKey: 'tips.travel.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.person_2_fill,
        titleKey: 'tips.travel.s3t',
        bodyKey: 'tips.travel.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_pie_fill,
        titleKey: 'tips.travel.s4t',
        bodyKey: 'tips.travel.s4b',
      ),
    ],
  ),

  _Topic(
    titleKey: 'tips.group.title',
    subtitleKey: 'tips.group.sub',
    icon: CupertinoIcons.heart_fill,
    color: Color(0xFFFF375F),
    steps: [
      _TipStep(
        icon: CupertinoIcons.arrow_2_squarepath,
        titleKey: 'tips.group.s1t',
        bodyKey: 'tips.group.s1b',
      ),
      _TipStep(
        icon: CupertinoIcons.person_2_fill,
        titleKey: 'tips.group.s2t',
        bodyKey: 'tips.group.s2b',
      ),
      _TipStep(
        icon: CupertinoIcons.plus_circle_fill,
        titleKey: 'tips.group.s3t',
        bodyKey: 'tips.group.s3b',
      ),
      _TipStep(
        icon: CupertinoIcons.chart_bar_fill,
        titleKey: 'tips.group.s4t',
        bodyKey: 'tips.group.s4b',
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
              context.t('tips.screenTitle'),
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
                context.t('tips.screenSubtitle'),
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
                        context.t(t.titleKey),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t(t.subtitleKey),
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
                  topicTitle: context.t(widget.topic.titleKey),
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
                              isLast
                                  ? context.t('common.done')
                                  : context.t('tips.next'),
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
              context
                  .t('tips.stepOf')
                  .replaceAll('{n}', '${widget.stepNumber}')
                  .replaceAll('{total}', '${widget.totalSteps}'),
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
            context.t(widget.step.titleKey),
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
            context.t(widget.step.bodyKey),
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
