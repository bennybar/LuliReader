import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import '../database/blacklist_dao.dart';
import '../database/feed_dao.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../models/feed.dart';

class BlacklistImportExportScreen extends ConsumerStatefulWidget {
  const BlacklistImportExportScreen({super.key});

  @override
  ConsumerState<BlacklistImportExportScreen> createState() => _BlacklistImportExportScreenState();
}

class _BlacklistImportExportScreenState extends ConsumerState<BlacklistImportExportScreen> {
  bool _isImporting = false;
  bool _isExporting = false;

  Future<void> _exportBlacklist() async {
    setState(() => _isExporting = true);
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) {
        throw Exception('No account found');
      }

      final blacklistDao = ref.read(blacklistDaoProvider);
      final feedDao = ref.read(feedDaoProvider);
      
      final entries = await blacklistDao.getAll(account.id!);
      final feeds = await feedDao.getAll(account.id!);

      if (entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No blacklist entries to export')),
          );
        }
        return;
      }

      // Build export content
      final lines = <String>[];
      for (final entry in entries) {
        if (entry.feedId == null) {
          lines.add('${entry.pattern}|ALL');
        } else {
          final feed = feeds.firstWhere(
            (f) => f.id == entry.feedId,
            orElse: () => Feed(
              id: entry.feedId!,
              name: 'Unknown',
              url: '',
              groupId: '',
              accountId: 0,
            ),
          );
          lines.add('${entry.pattern}|${feed.name}');
        }
      }
      final content = lines.join('\n');
      final contentBytes = utf8.encode(content);

      // Use FilePicker to let user choose where to save
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final fileName = 'luli_blacklist_$timestamp.txt';
      
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Blacklist Export',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt'],
        bytes: contentBytes,
      );

      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Blacklist exported successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting blacklist: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importBlacklist() async {
    setState(() => _isImporting = true);
    try {
      final accountService = ref.read(accountServiceProvider);
      final account = await accountService.getCurrentAccount();
      if (account == null) {
        throw Exception('No account found');
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() => _isImporting = false);
        return;
      }

      final file = File(result.files.single.path!);
      // Read file as UTF-8 bytes and decode explicitly to handle special characters
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: false);
      final lines = content.split('\n').where((line) => line.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File is empty or invalid')),
          );
        }
        return;
      }

      final blacklistDao = ref.read(blacklistDaoProvider);
      final feedDao = ref.read(feedDaoProvider);
      final feeds = await feedDao.getAll(account.id!);
      final existingEntries = await blacklistDao.getAll(account.id!);
      
      int imported = 0;
      int skipped = 0;

      for (final line in lines) {
        final parts = line.split('|');
        if (parts.isEmpty || parts[0].trim().isEmpty) continue;

        final pattern = parts[0].trim();
        String? feedId;

        if (parts.length > 1) {
          final feedNameOrAll = parts[1].trim();
          if (feedNameOrAll.toUpperCase() != 'ALL') {
            // Try to find feed by name
            final feed = feeds.firstWhere(
              (f) => f.name == feedNameOrAll,
              orElse: () => Feed(
                id: '',
                name: '',
                url: '',
                groupId: '',
                accountId: 0,
              ),
            );
            if (feed.id.isNotEmpty) {
              feedId = feed.id;
            } else {
              // Feed not found, skip this entry
              skipped++;
              continue;
            }
          }
        }

        // Check if entry already exists
        final exists = existingEntries.any((e) => 
          e.pattern == pattern && e.feedId == feedId
        );

        if (!exists) {
          final entry = BlacklistEntry(
            pattern: pattern,
            feedId: feedId,
            accountId: account.id!,
          );
          await blacklistDao.insert(entry);
          imported++;
        } else {
          skipped++;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported $imported entries${skipped > 0 ? ', skipped $skipped duplicates/unknown feeds' : ''}'),
          ),
        );
        // Pop back to blacklist screen which will refresh
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing blacklist: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blacklist Import/Export'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.upload_file,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Import Blacklist',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import blacklist entries from a .txt file. Each line should be in the format: pattern|feedName or pattern|ALL',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _importBlacklist,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(_isImporting ? 'Importing...' : 'Select .txt File'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.download,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Export Blacklist',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Export all your blacklist entries to a .txt file. You can use this to backup or transfer your blacklist.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isExporting ? null : _exportBlacklist,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isExporting ? 'Exporting...' : 'Export to .txt File'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

