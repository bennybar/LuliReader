import 'package:flutter/material.dart';

import '../services/sync_log_service.dart';
import '../theme/app_symbols.dart';
import '../widgets/settings_components.dart';

class SyncLogScreen extends StatefulWidget {
  const SyncLogScreen({super.key});

  @override
  State<SyncLogScreen> createState() => _SyncLogScreenState();
}

class _SyncLogScreenState extends State<SyncLogScreen> {
  final SyncLogService _syncLogService = SyncLogService();
  late Future<List<SyncLogEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _syncLogService.getLogEntries();
  }

  Future<void> _reload() async {
    setState(() {
      _entriesFuture = _syncLogService.getLogEntries();
    });
  }

  Future<void> _clearLogs() async {
    await _syncLogService.clearLogs();
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync history cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync history'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reload,
            icon: const Icon(AppSymbols.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<SyncLogEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? [];
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      AppSymbols.history,
                      size: 40,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No sync history yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Background and manual sync activity will appear here.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SettingsSectionHeader(
                title: 'Recent activity',
                subtitle: '${entries.length} entries saved on this device',
                action: TextButton(
                  onPressed: _clearLogs,
                  child: const Text('Clear'),
                ),
              ),
              SettingsGroup(
                children: [
                  for (final entry in entries) _SyncLogTile(entry: entry),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncLogTile extends StatelessWidget {
  const _SyncLogTile({required this.entry});

  final SyncLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = entry.success ? Colors.green : scheme.error;
    final status = entry.success
        ? '${entry.articlesSynced ?? 0} articles synced'
        : 'Error: ${entry.error ?? "Unknown error"}';
    final note = entry.note?.trim();
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          entry.success ? AppSymbols.check_circle : AppSymbols.error,
          size: 18,
          color: accent,
        ),
      ),
      title: Text(
        '${_typeLabel(entry.type)} • ${_formatTimeAgo(entry.timestamp)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        note == null || note.isEmpty ? status : '$status\n$note',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.3,
            ),
      ),
      isThreeLine: note != null && note.isNotEmpty,
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'background':
        return 'Background sync';
      case 'startup':
        return 'On app start';
      case 'manual':
      default:
        return 'Manual sync';
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    }
    if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    }
    if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'Just now';
  }
}
