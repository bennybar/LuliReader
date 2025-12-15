import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import 'feeds_page.dart';
import 'flow_page.dart';
import 'settings_screen.dart';

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  int _selectedIndex = 0;
  final GlobalKey<FeedsPageState> _feedsPageKey = GlobalKey();
  final GlobalKey<FlowPageState> _flowPageKey = GlobalKey();
  Timer? _syncTimer;
  bool _initialized = false;

  Future<void> _syncAll({bool showMessage = true}) async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      try {
        final rssService = ref.read(localRssServiceProvider);
        await rssService.sync(account.id!);
        if (mounted && showMessage) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync completed')),
          );
          // Refresh both pages
          _feedsPageKey.currentState?.refresh();
          _flowPageKey.currentState?.refresh();
        } else if (mounted) {
          // Silent refresh for periodic sync
          _feedsPageKey.currentState?.refresh();
          _flowPageKey.currentState?.refresh();
        }
      } catch (e) {
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
      if (account != null && account.syncInterval > 0) {
        _syncTimer = Timer.periodic(
          Duration(minutes: account.syncInterval),
          (_) => _syncAll(showMessage: false),
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
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
      print('Error saving default screen: $e');
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
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
          // Save default screen preference
          _saveDefaultScreen(index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Feeds',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Articles',
          ),
        ],
      ),
    );
  }
}

