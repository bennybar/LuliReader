import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../background/background_sync.dart';
import '../services/sync_log_service.dart';
import '../services/shared_preferences_service.dart';
import 'feeds_page.dart';
import 'flow_page.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final GlobalKey<FeedsPageState> _feedsPageKey = GlobalKey();
  final GlobalKey<FlowPageState> _flowPageKey = GlobalKey();
  Timer? _syncTimer;
  bool _initialized = false;
  bool _accountListenerSet = false;

  Future<void> _syncAll({bool showMessage = true}) async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      try {
        final articleDao = ref.read(articleDaoProvider);
        final countBefore = await articleDao.countByAccountId(account.id!);
        
        final syncCoordinator = ref.read(syncCoordinatorProvider);
        await syncCoordinator.syncAccount(account.id!); // Progress handled by FlowPage
        
        final countAfter = await articleDao.countByAccountId(account.id!);
        final articlesSynced = countAfter - countBefore;
        
        // Update last sync time
        await ref.read(accountServiceProvider).updateAccount(
              account.copyWith(updateAt: DateTime.now()),
            );
        ref.invalidate(currentAccountProvider);
        
        // Log sync
        final syncLog = SyncLogService();
        await syncLog.addLogEntry(SyncLogEntry(
          timestamp: DateTime.now(),
          type: showMessage ? 'manual' : 'startup',
          success: true,
          articlesSynced: articlesSynced,
        ));
        
        if (mounted) {
          // Refresh both pages
          _feedsPageKey.currentState?.refresh();
          _flowPageKey.currentState?.refresh();
        }
      } catch (e) {
        // Log failed sync
        final syncLog = SyncLogService();
        await syncLog.addLogEntry(SyncLogEntry(
          timestamp: DateTime.now(),
          type: showMessage ? 'manual' : 'startup',
          success: false,
          error: e.toString(),
        ));
        
        if (mounted && showMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sync error: $e')),
          );
        }
      }
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    Future.microtask(() async {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      final prefs = SharedPreferencesService();
      await prefs.init();
      final backgroundEnabled = await prefs.getBool('backgroundSyncEnabled') ?? true;
      if (account != null && account.syncInterval > 0) {
        _syncTimer = Timer.periodic(
          Duration(minutes: account.syncInterval),
          (_) => _syncAll(showMessage: false),
        );
        if (backgroundEnabled) {
          await registerBackgroundSync(
            account.syncInterval,
            requiresCharging: account.syncOnlyWhenCharging,
            requiresWiFi: account.syncOnlyOnWiFi,
          );
        } else {
          await cancelBackgroundSync();
        }
      } else {
        await cancelBackgroundSync();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDefaultScreen();
    _maybeSyncOnStart();
    // Start periodic sync after a short delay to allow widget tree to build
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _startPeriodicSync();
      }
    });
  }

  Future<void> _maybeSyncOnStart() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account?.syncOnStart == true) {
      // Delay slightly to allow UI build
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _syncAll(showMessage: false);
        }
      });
    }
  }

  Future<void> _loadDefaultScreen() async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null && mounted) {
      setState(() {
        _selectedIndex = account.defaultScreen;
        _initialized = true;
      });
    } else if (mounted) {
      setState(() {
        _initialized = true;
      });
    }
  }

  Future<void> _saveDefaultScreen(int screen) async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account != null && account.defaultScreen != screen) {
        final updatedAccount = account.copyWith(defaultScreen: screen);
        await ref.read(accountServiceProvider).updateAccount(updatedAccount);
      }
    } catch (e) {
      // Error saving default screen
    }
  }

  @override
  void didUpdateWidget(MainNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Restart sync if interval changed
    _startPeriodicSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _syncTimer?.cancel(); // Stop foreground sync when backgrounded
    } else if (state == AppLifecycleState.resumed) {
      _startPeriodicSync(); // Restart when resumed
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    if (!_accountListenerSet) {
      _accountListenerSet = true;
      ref.listen(currentAccountProvider, (_, __) {
        _startPeriodicSync();
      });
    }

    if (!_initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          FeedsPage(key: _feedsPageKey, onSync: _syncAll),
          FlowPage(key: _flowPageKey, onSync: _syncAll),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
              _saveDefaultScreen(index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder_rounded),
                label: 'Feeds',
              ),
              NavigationDestination(
                icon: Icon(Icons.article_outlined),
                selectedIcon: Icon(Icons.article_rounded),
                label: 'Articles',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

