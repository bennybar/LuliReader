import 'package:flutter/material.dart';

class SyncProgressDialog extends StatefulWidget {
  final Future<void> Function(void Function(String) onProgress) syncFunction;

  const SyncProgressDialog({
    super.key,
    required this.syncFunction,
  });

  @override
  State<SyncProgressDialog> createState() => _SyncProgressDialogState();
}

class _SyncProgressDialogState extends State<SyncProgressDialog> {
  String _currentStatus = 'Starting sync...';
  final List<String> _logMessages = [];
  bool _isComplete = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    try {
      await widget.syncFunction((message) {
        if (mounted) {
          setState(() {
            _currentStatus = message;
            _logMessages.add('${DateTime.now().toString().substring(11, 19)}: $message');
            // Keep only last 50 messages
            if (_logMessages.length > 50) {
              _logMessages.removeAt(0);
            }
          });
        }
      });
      
      if (mounted) {
        setState(() {
          _isComplete = true;
          _currentStatus = 'Sync completed successfully!';
        });
        // Auto-close after 2 seconds
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _currentStatus = 'Error: $e';
          _logMessages.add('${DateTime.now().toString().substring(11, 19)}: ERROR - $e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isComplete || _error != null,
      child: AlertDialog(
        title: Row(
          children: [
            if (!_isComplete && _error == null)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_error != null)
              Icon(Icons.error, color: Theme.of(context).colorScheme.error)
            else
              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('Syncing Feeds')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentStatus,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _error != null
                            ? Theme.of(context).colorScheme.error
                            : _isComplete
                                ? Theme.of(context).colorScheme.primary
                                : null,
                      ),
                ),
                if (_logMessages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Log:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _logMessages.length,
                      itemBuilder: (context, index) {
                        final message = _logMessages[index];
                        final isError = message.contains('ERROR');
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            message,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: isError
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (_isComplete || _error != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(_error == null),
              child: Text(_error != null ? 'Close' : 'Done'),
            ),
        ],
      ),
    );
  }
}

