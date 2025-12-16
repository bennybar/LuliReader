import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workmanager/workmanager.dart';
import 'theme/app_theme.dart';
import 'screens/startup_screen.dart';
import 'background/background_sync.dart';
import 'providers/app_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSyncDispatcher, isInDebugMode: false);
  runApp(const ProviderScope(child: LuliReaderApp()));
}

class LuliReaderApp extends ConsumerWidget {
  const LuliReaderApp({super.key});

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
    );
  }
}
