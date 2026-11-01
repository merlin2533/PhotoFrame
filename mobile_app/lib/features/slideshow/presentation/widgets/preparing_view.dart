import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../cache/small_photo_cache.dart';

/// Full-screen progress shown while the slideshow waits for its first
/// screen-sized photo copies (see `_preferPrepared` in `slideshow_screen.dart`),
/// instead of an empty screen.
///
/// Watches [smallPhotoWorkerProvider], so the progress bar updates live. While
/// the worker has not reported a total yet, the bar is indeterminate and the
/// text has no count.
class PreparingView extends ConsumerWidget {
  const PreparingView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(smallPhotoWorkerProvider);
    final hasTotal = status.total > 0;
    final value = hasTotal ? status.done / status.total : null;
    final progressText = hasTotal
        ? l10n.preparingProgress(status.done, status.total)
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
            ],
          ),
        ),
      ),
    );
  }
}
