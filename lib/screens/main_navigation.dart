import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import '../background/background_sync.dart';
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
  bool _accountListenerSet = false;

  Future<void> _syncAll({bool showMessage = true}) async {
    final account = await ref.read(accountServiceProvider).getCurrentAccount();
    if (account != null) {
      try {
        final rssService = ref.read(localRssServiceProvider);
        await rssService.sync(account.id!);
        // Update last sync time
        await ref.read(accountServiceProvider).updateAccount(
              account.copyWith(updateAt: DateTime.now()),
            );
        ref.invalidate(currentAccountProvider);
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
        await registerBackgroundSync(account.syncInterval);
      } else {
        await cancelBackgroundSync();
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
    _syncTimer?.cancel();
    super.dispose();
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
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: [
              FeedsPage(key: _feedsPageKey, onSync: _syncAll),
              FlowPage(key: _flowPageKey, onSync: _syncAll),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
              child: _buildGlassNavBar(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassNavBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glassColor = scheme.surface.withOpacity(0.18);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: glassColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: scheme.onSurface.withOpacity(0.06),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavButton(
                context,
                index: 0,
                label: 'Feeds',
                icon: Icons.folder,
              ),
              const SizedBox(width: 12),
              _buildNavButton(
                context,
                index: 1,
                label: 'Articles',
                icon: Icons.article,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(BuildContext context,
      {required int index, required String label, required IconData icon}) {
    final isSelected = _selectedIndex == index;
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color:
              isSelected ? colorScheme.primary.withOpacity(0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              setState(() {
                _selectedIndex = index;
              });
              _saveDefaultScreen(index);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary.withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface.withOpacity(0.75),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withOpacity(0.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

