import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_log_buffer.dart';
import '../../../l10n/app_localizations.dart';
import '../state/app_log_providers.dart';

/// Shows the in-memory log of recovered errors (newest first), with actions
/// to copy the whole log as text and to clear it after confirmation.
///
/// The log lives only in memory and is lost on restart. It holds no stack
/// traces, only time, level, message and the short error text.
class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final entries = ref.watch(appLogEntriesProvider);
    final hasEntries = entries.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: l10n.logCopyAction,
            onPressed: hasEntries ? () => _copyAll(context, entries) : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: l10n.logClearAction,
            onPressed: hasEntries ? () => _confirmClear(context, ref) : null,
          ),
        ],
      ),
      body: hasEntries
          ? ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _LogEntryTile(entry: entries[index]),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.logEmptyState,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }

  Future<void> _copyAll(BuildContext context, List<AppLogEntry> entries) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(
      ClipboardData(text: formatAppLogEntriesAsText(entries)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.logCopiedMessage)));
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logClearConfirmTitle),
        content: Text(l10n.logClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.logClearAction),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(appLogEntriesProvider.notifier).clear();
    }
  }
}

class _LogEntryTile extends StatelessWidget {
  const _LogEntryTile({required this.entry});

  final AppLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = entry.level == AppLogLevel.error;
    final details = [
      '${formatAppLogTime(entry.time)} · ${entry.level.label}',
      if (entry.errorText != null) entry.errorText!,
    ].join('\n');

    return ListTile(
      leading: Icon(
        isError ? Icons.error_outline : Icons.info_outline,
        color: isError ? theme.colorScheme.error : theme.colorScheme.outline,
      ),
      title: Text(entry.message),
      subtitle: Text(details),
      isThreeLine: entry.errorText != null,
    );
  }
}
