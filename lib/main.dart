import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui' as ui;

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/background_sync_service.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize notification service for badge updates
  await NotificationService.initialize();
  runApp(const LuliReaderApp());
}

class LuliReaderApp extends StatefulWidget {
  const LuliReaderApp({super.key});

  @override
  State<LuliReaderApp> createState() => _LuliReaderAppState();
}

class _LuliReaderAppState extends State<LuliReaderApp> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final storage = StorageService();
    final loggedIn = await storage.isLoggedIn();
    
    // Initialize background sync if logged in
    if (loggedIn) {
      await BackgroundSyncService.initialize();
      final config = await storage.getUserConfig();
      if (config != null) {
        await BackgroundSyncService.scheduleSync(config.backgroundSyncIntervalMinutes);
      }
      // Update badge count on app start
      await NotificationService.updateBadgeCount();
    } else {
      // Clear badge if not logged in
      await NotificationService.clearBadge();
    }
    
    setState(() {
      _isLoggedIn = loggedIn;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Detect system locale for RTL
    final systemLocale = ui.PlatformDispatcher.instance.locale;
    final isRTL = systemLocale.languageCode == 'he' || systemLocale.languageCode == 'ar';
    print('System locale: $systemLocale, isRTL: $isRTL');
    
    final app = MaterialApp(
      title: 'LuliReader',
      debugShowCheckedModeBanner: false,
      // RTL support
      supportedLocales: const [
        Locale('en', ''),
        Locale('he', ''),
        Locale('ar', ''),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      locale: systemLocale,
      builder: (context, child) {
        // Force RTL if Hebrew or Arabic
        final textDir = isRTL ? ui.TextDirection.rtl : ui.TextDirection.ltr;
        return Directionality(
          textDirection: textDir,
          child: child!,
        );
      },
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: _isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );

    return app;
  }
  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 60,
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer.withOpacity(0.4),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
