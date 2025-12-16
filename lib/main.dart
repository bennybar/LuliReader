import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_analytics/observer.dart';
import 'theme/app_theme.dart';
import 'screens/startup_screen.dart';
import 'background/background_sync.dart';
import 'providers/app_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await Workmanager().initialize(backgroundSyncDispatcher, isInDebugMode: false);
  final analytics = FirebaseAnalytics.instance;
  final observer = FirebaseAnalyticsObserver(analytics: analytics);
  runApp(ProviderScope(child: LuliReaderApp(analytics: analytics, observer: observer)));
}

class LuliReaderApp extends ConsumerWidget {
  const LuliReaderApp({
    super.key,
    this.analytics,
    this.observer,
  });

  final FirebaseAnalytics? analytics;
  final FirebaseAnalyticsObserver? observer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeNotifierProvider);
    return MaterialApp(
      title: 'Luli Reader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(null),
      darkTheme: AppTheme.darkTheme(null),
      themeMode: themeMode,
      home: const StartupScreen(),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      supportedLocales: const [
        Locale('en', ''),
        Locale('he', ''), // Hebrew
        Locale('ar', ''), // Arabic
        Locale('fa', ''), // Persian
      ],
      navigatorObservers: observer != null ? [observer!] : const [],
    );
  }
}
