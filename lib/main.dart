import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app_config.dart';
import 'firebase_options.dart';
import 'supabase_config.dart';
import 'repositories/local_storage.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/expenses/quick_add_sheet.dart';
import 'screens/expenses/voice_add_sheet.dart';
import 'screens/home/home_shell.dart';
import 'models/account.dart';
import 'models/expense.dart';
import 'services/deep_link_service.dart';
import 'services/i18n.dart';
import 'services/interest_service.dart';
import 'services/live_activity_service.dart';
import 'services/prefs_service.dart';
import 'services/voice_expense_parser.dart';
import 'services/widget_intent_service.dart';
import 'services/widget_sync_service.dart';
import 'state/providers.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TrackoraBootstrap()));
}

class TrackoraBootstrap extends StatefulWidget {
  const TrackoraBootstrap({super.key});

  @override
  State<TrackoraBootstrap> createState() => _TrackoraBootstrapState();
}

class _TrackoraBootstrapState extends State<TrackoraBootstrap> {
  late final Future<void> _startup = _start();

  Future<void> _start() async {
    if (storageMode == StorageMode.firebase) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    }
    // Load locale data so DateFormat (month/day names) can render in zh / ms,
    // not just English. Intl.defaultLocale is kept in sync in TrackoraApp.build.
    await initializeDateFormatting();

    // Always init local storage — used as offline cache for group expenses
    // even in Firebase mode.
    await LocalStorage.init();

    // Widget syncing is useful, but it should never block the main app from
    // rendering. If a platform channel is unavailable during launch, the
    // dashboard's next widget push can reconcile later.
    try {
      await WidgetSyncService().init();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError) {
          return const TrackoraApp();
        }

        return MaterialApp(
          title: 'Trackora',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: snapshot.hasError
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Startup failed:\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const CupertinoActivityIndicator(),
            ),
          ),
        );
      },
    );
  }
}

class TrackoraApp extends ConsumerStatefulWidget {
  const TrackoraApp({super.key});

  @override
  ConsumerState<TrackoraApp> createState() => _TrackoraAppState();
}

class _TrackoraAppState extends ConsumerState<TrackoraApp>
    with WidgetsBindingObserver {
  static const _shareChannel = MethodChannel('trackora/share_import');
  final _widgetIntents = WidgetIntentService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cold start drain — pulls any quick-add entries the widget queued
    // while the app was killed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.attach(rootNavKey);
      _drainWidgetQueue();
      _maybeOpenQuickAdd();
      _maybeOpenVoiceAdd();
      _restoreLiveActivity();
      _accrueInterest();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _drainWidgetQueue();
      _maybeOpenQuickAdd();
      _maybeOpenVoiceAdd();
      // Detect a share that was made while the app was in background.
      // Covers the case where extensionContext.open() didn't fire the URL.
      DeepLinkService.checkAndOpenPendingShare(rootNavKey);
      // Push fresh data to Watch on every foreground resume so the Watch
      // has up-to-date stats without needing the user to open the phone app.
      _syncToWatch();
      // Restore Live Activity if user has it enabled (handles iOS end-of-life
      // after the system's 12-hour limit and cold restarts).
      _restoreLiveActivity();
      // Catch up any interest that came due while the app was backgrounded.
      _accrueInterest();
    }
  }

  /// Accrues any due interest on interest-bearing accounts (best-effort).
  Future<void> _accrueInterest() async {
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) return;
      final accountRepo = ref.read(accountRepositoryProvider);
      final expenseRepo = ref.read(expenseRepositoryProvider);
      final accounts = await accountRepo
          .getAll(user.uid)
          .first
          .timeout(const Duration(seconds: 8), onTimeout: () => const <Account>[]);
      final bearing = accounts
          .where((a) =>
              (a.interestRatePercent ?? 0) > 0 && a.interestPeriod != null)
          .toList();
      if (bearing.isEmpty) return;
      final all = await expenseRepo
          .getAllExpenses(user.uid)
          .first
          .timeout(const Duration(seconds: 8), onTimeout: () => const <Expense>[]);
      final balances = computeAccountBalanceMap(accounts, all);
      final converter = ref.read(currencyConverterProvider).valueOrNull;
      final localeCode = ref.read(localeProvider).encode();
      final note = AppStrings(localeCode == 'system' ? 'en' : localeCode)
          .t('account.interestNote');
      await InterestService.accrueDue(
        userId: user.uid,
        accountRepo: accountRepo,
        expenseRepo: expenseRepo,
        accounts: bearing,
        balances: balances,
        noteLabel: note,
        toBase: converter != null
            ? (amt, code) => converter.toBase(amt, code)
            : null,
        baseCurrencyCode: converter?.base,
      );
    } catch (_) {
      // Interest accrual is best-effort; never block app startup.
    }
  }

  Future<void> _restoreLiveActivity() async {
    final prefs = PrefsService();
    final enabled = await prefs.liveActivityEnabled();
    if (!enabled) return;
    final currency = await prefs.currencySymbol();
    // Start with 0 todaySpent; WidgetSyncService.push() on the same resume
    // cycle will call LiveActivityService.update() with the real value.
    await LiveActivityService.start(currency: currency, todaySpent: 0);
  }

  Future<void> _syncToWatch() async {
    try {
      await ref.read(watchServiceProvider).syncToWatch();
    } catch (_) {
      // Watch sync is best-effort.
    }
  }

  Future<void> _drainWidgetQueue() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      await _widgetIntents.drain(user.uid, ref.read(expenseRepositoryProvider));
    } catch (_) {
      // Drain is best-effort; failures are non-fatal.
    }
  }

  /// Drains the iOS App Shortcut trigger flag and routes to the right action:
  ///
  /// - Pending image (shared screenshot / notification receipt) → OCR confirmation.
  /// - No pending image → Quick Add sheet.
  Future<void> _maybeOpenQuickAdd() async {
    final pending = await _widgetIntents.consumePendingQuickAdd();
    if (!pending) return;

    // If a shared/notification receipt image is waiting, OCR it instead.
    try {
      final result = await _shareChannel.invokeMethod<Map<Object?, Object?>>(
        'checkPendingShare',
      );
      if (result != null && result.isNotEmpty) {
        DeepLinkService.openImportScreenForBackTap(rootNavKey);
        return;
      }
    } catch (_) {}

    // No pending image → original Quick Add behaviour.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavKey.currentContext;
      if (ctx == null) return;
      QuickAddSheet.show(ctx);
    });
  }

  /// Drains a phrase captured by the "Add Expense by Voice" Siri App Intent,
  /// parses it, and opens the confirmation screen pre-filled. Never auto-saves.
  Future<void> _maybeOpenVoiceAdd() async {
    final phrase = await _widgetIntents.consumePendingVoicePhrase();
    if (phrase == null) return;
    final base = ref.read(currencyCodeProvider).valueOrNull;
    final parsed = const VoiceExpenseParser().parse(phrase, defaultCurrency: base);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavKey.currentContext;
      if (ctx == null) return;
      pushVoiceExpenseConfirmation(ctx, parsed);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoSyncProvider); // keep offline→online sync listener alive
    ref.watch(customCategoryStyleRegistryProvider); // keep custom styles fresh
    final auth = ref.watch(authStateProvider);

    // Attach the Apple Watch bridge once we have a signed-in / offline user.
    // The bridge listens for "addExpense" messages from the paired watch and
    // writes them through the active ExpenseRepository (Hive or Firestore).
    final currentUser = auth.valueOrNull;
    if (currentUser != null) {
      ref
          .read(watchServiceProvider)
          .attach(
            userId: currentUser.uid,
            repository: ref.read(expenseRepositoryProvider),
            accountRepository: ref.read(accountRepositoryProvider),
            prefsService: ref.read(prefsServiceProvider),
            onSessionActivated: () =>
                ref.read(widgetSyncServiceProvider).repushToWatch(),
          );
      // Drain the queue once the user is known (covers the case where
      // auth resolves after our cold-start drain ran).
      _drainWidgetQueue();
    }
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user == null) return;
      ref
          .read(watchServiceProvider)
          .attach(
            userId: user.uid,
            repository: ref.read(expenseRepositoryProvider),
            accountRepository: ref.read(accountRepositoryProvider),
            prefsService: ref.read(prefsServiceProvider),
            onSessionActivated: () =>
                ref.read(widgetSyncServiceProvider).repushToWatch(),
          );
      _drainWidgetQueue();
    });

    final themeMode = ref.watch(themeModeProvider);
    // Resolve dark vs. light right now so the status bar icons match.
    final platformBrightness = MediaQuery.platformBrightnessOf(context);
    final effectiveBrightness = switch (themeMode) {
      ThemeMode.system => platformBrightness,
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
    };
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: effectiveBrightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: effectiveBrightness,
      ),
    );

    final appLocale = ref.watch(localeProvider).toLocale();
    // Drive bare DateFormat(...) calls (e.g. "Jun 2026") off the active locale
    // so dates localize everywhere without threading a locale through each call.
    // `system` mode (appLocale == null) follows the device language.
    Intl.defaultLocale = appLocale?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return MaterialApp(
      title: 'Trackora',
      navigatorKey: rootNavKey,
      debugShowCheckedModeBanner: false,
      // Clamp the system text scale so large Dynamic Type / accessibility
      // sizes never break the layout into clipped or overlapping text
      // (keeps typography readable on iPad and large displays), while still
      // honouring moderate text-size preferences.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.3,
            ),
          ),
          // Tap any empty space to dismiss the keyboard / numpad app-wide.
          // Translucent so taps still reach buttons, fields and scroll views;
          // only taps that nothing else handles fall through to here.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              final focus = FocusManager.instance.primaryFocus;
              if (focus != null && focus.hasFocus) focus.unfocus();
            },
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: appLocale,
      // `flutter_localizations` provides Material / Cupertino translations
      // for system widgets (e.g. CupertinoDatePicker month names). Our
      // own strings come from `AppStrings` via `context.t(...)`.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ms')],
      home: auth.when(
        data: (user) => user == null
            ? const _AuthGate()
            : const HomeShell(),
        loading: () => Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: const Center(child: CupertinoActivityIndicator()),
        ),
        error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      ),
    );
  }
}

/// Shows WelcomeScreen on first launch; LoginScreen on subsequent launches.
/// If Firebase already has a valid cached user (during the brief persistence-
/// loading window before authStateChanges fires), shows a spinner instead of
/// the login form so Face ID is never prompted for an already-valid session.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    // Firebase persistence may restore the session slightly after the stream
    // emits null. If a *verified* currentUser is already set, wait for the auth
    // stream to catch up and navigate to HomeShell — never show the login form.
    // An unverified cached session must fall through to the login screen so the
    // email-verification gate is enforced.
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser != null && fbUser.emailVerified) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator()),
      );
    }
    return FutureBuilder<bool>(
      future: hasSeenWelcome(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CupertinoActivityIndicator()),
          );
        }
        return snapshot.data! ? const LoginScreen() : const WelcomeScreen();
      },
    );
  }
}
