import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'dart:convert';
import '../providers/app_provider.dart';
import '../widgets/sync_progress_dialog.dart';

class OpmlImportExportScreen extends ConsumerStatefulWidget {
  const OpmlImportExportScreen({super.key});

  @override
  ConsumerState<OpmlImportExportScreen> createState() => _OpmlImportExportScreenState();
}

class _OpmlImportExportScreenState extends ConsumerState<OpmlImportExportScreen> {
  bool _isImporting = false;
  bool _isExporting = false;

  Future<void> _importOpml() async {
    setState(() => _isImporting = true);

    try {
      // Try with specific extensions first
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['opml', 'xml'],
        allowMultiple: false,
        withData: true, // Read file data directly (works with cloud storage)
        withReadStream: false,
      );

      // If no result or file not accessible, try with any file type
      if (result == null || (result.files.single.path == null && result.files.single.bytes == null)) {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: false,
          withData: true,
          withReadStream: false,
        );
      }

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      final pickedFile = result.files.single;
      String content;

      // Try to read from bytes first (works with cloud storage)
      if (pickedFile.bytes != null) {
        content = utf8.decode(pickedFile.bytes!);
      } else if (pickedFile.path != null) {
        // Fallback to reading from local path
        final file = File(pickedFile.path!);
        content = await file.readAsString();
      } else {
        throw Exception('Unable to access file. Please ensure the file is available and try again.');
      }

      // Validate that the content looks like OPML/XML
      if (!content.trim().startsWith('<?xml') && !content.trim().startsWith('<opml')) {
        // Check if it's at least XML-like
        if (!content.contains('<') || !content.contains('>')) {
          throw Exception('Selected file does not appear to be a valid OPML/XML file. Please select an OPML file.');
        }
      }

      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        throw Exception('No account found');
      }

      final opmlService = ref.read(opmlServiceProvider);
      await opmlService.importFromString(content, account.id!);
      
      if (!mounted) return;

      if (!mounted) return;

      // Show sync progress dialog
      final syncResult = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => SyncProgressDialog(
          syncFunction: (onProgress) async {
            final localRssService = ref.read(localRssServiceProvider);
            await localRssService.sync(account.id!, onProgress: onProgress);
          },
        ),
      );

      if (!mounted) return;

      if (syncResult == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OPML imported and synced successfully!'),
            duration: Duration(seconds: 2),
          ),
        );
      } else if (syncResult == false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OPML imported but sync had errors. Check logs.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // Pop and refresh home screen
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing OPML: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _exportOpml() async {
    setState(() => _isExporting = true);

    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) {
        throw Exception('No account found');
      }

      final opmlService = ref.read(opmlServiceProvider);
      final opmlContent = await opmlService.exportToString(account.id!, attachInfo: true);

      if (!mounted) return;

      await Share.share(
        opmlContent,
        subject: 'Luli Reader Feeds Export',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting OPML: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OPML Import/Export'),
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
                          'Import OPML',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Import feeds from an OPML file. This will add all feeds and groups to your current account.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isImporting ? null : _importOpml,
                      icon: _isImporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload),
                      label: Text(_isImporting ? 'Importing...' : 'Select OPML File'),
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
                          'Export OPML',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Export all your feeds and groups to an OPML file. You can use this to backup or transfer your feeds.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _isExporting ? null : _exportOpml,
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_isExporting ? 'Exporting...' : 'Export OPML'),
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

