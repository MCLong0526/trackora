import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/i18n.dart';
import '../../services/voice_expense_parser.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_expense_screen.dart';

/// Pushes the manual-confirmation screen pre-filled from a parsed phrase. Shared
/// by the in-app voice sheet and the Siri App Intent drain. Never auto-saves —
/// the user reviews and taps Save on [AddEditExpenseScreen].
void pushVoiceExpenseConfirmation(
  BuildContext context,
  ParsedExpense parsed,
) {
  Navigator.of(context, rootNavigator: true).push(
    CupertinoPageRoute(
      fullscreenDialog: true,
      builder: (_) => AddEditExpenseScreen(
        initialAmount: parsed.amount,
        initialNote: parsed.note,
        initialCategory: parsed.category,
        initialDate: parsed.date,
        initialCurrencyCode: parsed.currencyCode,
      ),
    ),
  );
}

/// Bottom sheet that captures a spoken expense with on-device speech
/// recognition (Apple Speech / Android SpeechRecognizer), then opens the
/// confirmation screen. Falls back to a text field when speech is unavailable
/// or the parse is incomplete.
class VoiceAddSheet extends ConsumerStatefulWidget {
  const VoiceAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceAddSheet(),
    );
  }

  @override
  ConsumerState<VoiceAddSheet> createState() => _VoiceAddSheetState();
}

enum _VoiceState { initializing, listening, done, unavailable }

class _VoiceAddSheetState extends ConsumerState<VoiceAddSheet> {
  final SpeechToText _speech = SpeechToText();
  final TextEditingController _manualCtrl = TextEditingController();
  _VoiceState _state = _VoiceState.initializing;
  String _transcript = '';
  bool _speechReady = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _speech.cancel();
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: _onStatus,
        onError: (_) {
          if (mounted && _state == _VoiceState.listening) {
            setState(() => _state = _VoiceState.done);
          }
        },
      );
    } catch (_) {
      _speechReady = false;
    }
    if (!mounted) return;
    if (!_speechReady) {
      setState(() => _state = _VoiceState.unavailable);
      return;
    }
    _startListening();
  }

  void _onStatus(String status) {
    // "done"/"notListening" fire when the recognizer stops on its own.
    if (!mounted) return;
    if ((status == 'done' || status == 'notListening') &&
        _state == _VoiceState.listening) {
      setState(() => _state = _VoiceState.done);
    }
  }

  Future<void> _startListening() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _state = _VoiceState.listening;
      _transcript = '';
    });
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() => _transcript = result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _stopAndParse() async {
    if (_speech.isListening) {
      await _speech.stop();
    }
    final text = _transcript.trim();
    if (text.isEmpty) {
      setState(() => _state = _VoiceState.unavailable);
      return;
    }
    _confirm(text);
  }

  void _confirm(String text) {
    final base = ref.read(currencyCodeProvider).valueOrNull;
    final parsed = const VoiceExpenseParser()
        .parse(text, defaultCurrency: base);
    if (!parsed.hasAmount) {
      // Let the user fix the phrase before opening the form.
      _manualCtrl.text = text;
      setState(() => _state = _VoiceState.unavailable);
      if (mounted) {
        AppToast.show(context, context.t('voice.noAmount'),
            type: AppToastType.info);
      }
      return;
    }
    // Capture the root navigator before popping the sheet so the push doesn't
    // run against a deactivated context.
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    rootNav.push(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddEditExpenseScreen(
          initialAmount: parsed.amount,
          initialNote: parsed.note,
          initialCategory: parsed.category,
          initialDate: parsed.date,
          initialCurrencyCode: parsed.currencyCode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: brand.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.t('voice.title'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('voice.example'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: brand.inkSoft, height: 1.4),
          ),
          const SizedBox(height: 22),
          if (_state == _VoiceState.unavailable)
            _buildManualFallback(brand)
          else
            _buildListening(brand),
        ],
      ),
    );
  }

  Widget _buildListening(BrandColors brand) {
    final listening = _state == _VoiceState.listening;
    return Column(
      children: [
        // Mic orb.
        GestureDetector(
          onTap: listening ? _stopAndParse : _startListening,
          child: _PulsingMic(active: listening),
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Text(
            _transcript.isEmpty
                ? context.t(listening ? 'voice.listening' : 'voice.tapToSpeak')
                : _transcript,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _transcript.isEmpty ? 14 : 17,
              fontWeight:
                  _transcript.isEmpty ? FontWeight.w400 : FontWeight.w600,
              color: _transcript.isEmpty ? brand.inkSoft : brand.ink,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: brand.accentDark,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(vertical: 15),
            onPressed: _transcript.trim().isEmpty ? null : _stopAndParse,
            child: Text(
              context.t('voice.useThis'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: brand.background,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        CupertinoButton(
          onPressed: () => setState(() => _state = _VoiceState.unavailable),
          child: Text(
            context.t('voice.typeInstead'),
            style: TextStyle(fontSize: 14, color: brand.inkSoft),
          ),
        ),
      ],
    );
  }

  Widget _buildManualFallback(BrandColors brand) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            border: Border.all(color: brand.divider),
          ),
          child: TextField(
            controller: _manualCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(fontSize: 16, color: brand.ink),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) _confirm(v.trim());
            },
            decoration: InputDecoration(
              filled: false,
              border: InputBorder.none,
              hintText: context.t('voice.example'),
              hintStyle: TextStyle(fontSize: 15, color: brand.inkSoft),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: CupertinoButton(
            color: brand.accentDark,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.symmetric(vertical: 15),
            onPressed: () {
              final v = _manualCtrl.text.trim();
              if (v.isNotEmpty) _confirm(v);
            },
            child: Text(
              context.t('voice.continueLabel'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: brand.background,
              ),
            ),
          ),
        ),
        if (_speechReady) ...[
          const SizedBox(height: 8),
          CupertinoButton(
            onPressed: () {
              setState(() => _state = _VoiceState.done);
              _startListening();
            },
            child: Text(
              context.t('voice.speakInstead'),
              style: TextStyle(fontSize: 14, color: brand.inkSoft),
            ),
          ),
        ],
      ],
    );
  }
}

/// Animated microphone orb that pulses while listening.
class _PulsingMic extends StatefulWidget {
  final bool active;
  const _PulsingMic({required this.active});

  @override
  State<_PulsingMic> createState() => _PulsingMicState();
}

class _PulsingMicState extends State<_PulsingMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accent = AppActionBlue.color;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = widget.active ? _ctrl.value : 0.0;
        final ringSize = 96.0 + t * 22.0;
        return SizedBox(
          width: 130,
          height: 130,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: ringSize,
                  height: ringSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: widget.active ? 0.12 : 0.06),
                  ),
                ),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.active ? accent : brand.surface,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.25),
                        blurRadius: widget.active ? 18 : 0,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(
                    CupertinoIcons.mic_fill,
                    size: 30,
                    color: widget.active ? Colors.white : brand.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
