import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide LocalStorage;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';
import 'firebase_options.dart';
import 'supabase_config.dart';
import 'repositories/local_storage.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/expenses/quick_add_sheet.dart';
import 'screens/home/home_shell.dart';
import 'services/deep_link_service.dart';
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
    } else {
      await LocalStorage.init();
    }

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
      // Push fresh data to Watch on every foreground resume so the Watch
      // has up-to-date stats without needing the user to open the phone app.
      _syncToWatch();
    }
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

  /// Drains the iOS App Shortcut "Quick Add Expense" trigger flag.
  /// Set by `OpenQuickAddIntent` when the user invokes the shortcut
  /// from Back Tap, Siri, the Action Button, or the Shortcuts app.
  Future<void> _maybeOpenQuickAdd() async {
    final pending = await _widgetIntents.consumePendingQuickAdd();
    if (!pending) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = rootNavKey.currentContext;
      if (ctx == null) return;
      QuickAddSheet.show(ctx);
    });
  }

  @override
  Widget build(BuildContext context) {
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
    return MaterialApp(
      title: 'Trackora',
      navigatorKey: rootNavKey,
      debugShowCheckedModeBanner: false,
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
    // emits null. If currentUser is already set, wait for the auth stream to
    // catch up and navigate to HomeShell — never show the login form.
    if (FirebaseAuth.instance.currentUser != null) {
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
