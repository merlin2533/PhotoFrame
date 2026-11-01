import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/byte_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../cache/small_photo_cache.dart';

/// Full-screen progress shown while the slideshow waits for its first
/// screen-sized photo copies (see `_startPool` in `slideshow_screen.dart`),
/// instead of an empty screen.
///
/// Watches [smallPhotoWorkerProvider], so the progress bar and the detail
/// lines below it update live: done and queued photos, downloaded bytes, the
/// download speed and the open conversions. While the worker has not reported
/// a total yet, the bar is indeterminate and the text has no count.
class PreparingView extends ConsumerWidget {
  const PreparingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final status = ref.watch(smallPhotoWorkerProvider);
    final hasTotal = status.total > 0;
    final value = hasTotal ? status.done / status.total : null;
    final progressText = hasTotal
        ? l10n.preparingProgressQueue(
            status.done, status.total, status.waiting)
        : l10n.preparingProgressUnknown;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.preparingTitle,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: LinearProgressIndicator(value: value),
              ),
              const SizedBox(height: 16),
              Text(progressText, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                l10n.preparingDownloaded(
                    formatBytes(status.downloadedBytes, locale)),
                textAlign: TextAlign.center,
              ),
              Text(
                l10n.preparingRate(formatRate(status.downloadRate, locale)),
                textAlign: TextAlign.center,
              ),
              Text(
                l10n.preparingConversions(status.openConversions),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
