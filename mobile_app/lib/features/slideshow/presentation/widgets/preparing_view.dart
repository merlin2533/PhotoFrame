import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/byte_format.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../cache/prepared_count_provider.dart';
import '../../../cache/small_photo_cache.dart';
import '../../../settings/domain/app_settings.dart';
import '../../../settings/state/settings_providers.dart';
import '../../domain/daily_selection.dart';
import '../../domain/rotation_swap.dart';
import '../daily_swap_text.dart';

/// Whether the daily swap already ran today, from the day stored under
/// [rotationSwapDayPrefsKey].
final FutureProvider<bool> _swappedTodayProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider);
  final today = DailySelection.dayKey(DateTime.now());
  return !swapDue(
    lastSwapDay: prefs.getString(rotationSwapDayPrefsKey),
    today: today,
  );
});

/// Full-screen progress shown while the slideshow waits for its first
/// screen-sized photo copies (see `_startPool` in `slideshow_screen.dart`),
/// instead of an empty screen.
///
/// Watches [smallPhotoWorkerProvider], so the progress bar and the detail
/// lines below it update live: done and queued photos, downloaded bytes, the
/// download speed and the open conversions. While the worker has not reported
/// a total yet, the bar is indeterminate and the text has no count.
///
/// Below that it shows what is already on disk: the prepared photos in the
/// cache, the daily swap percent and, when [poolSize] is known, how many
/// photos the swap changes per day and how many it changed today.
class PreparingView extends ConsumerWidget {
  const PreparingView({super.key, this.poolSize});

  /// Number of photos in the rotation pool, or `null` while it is not known.
  final int? poolSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final status = ref.watch(smallPhotoWorkerProvider);
    // Re-count the cache whenever the worker finished another photo.
    ref.listen<int>(
      smallPhotoWorkerProvider.select((status) => status.done),
      (_, __) => ref.invalidate(preparedCountProvider),
    );
    final cached = ref.watch(preparedCountProvider).value;
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final percent = settings.rotationSwapPercent;
    final swappedToday = ref.watch(_swappedTodayProvider).value ?? false;

    final hasTotal = status.total > 0;
    final value = hasTotal ? status.done / status.total : null;
    final progressText = hasTotal
        ? l10n.preparingProgressQueue(status.done, status.total, status.waiting)
        : l10n.preparingProgressUnknown;

    final pool = poolSize;
    // Swapped today: the swap replaces the same number of photos it would
    // replace on any day with this pool, so the count is derived from it.
    final swappedCount = pool != null && swappedToday
        ? rotationSwapSize(pool, percent: percent)
        : 0;

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
              if (cached != null)
                Text(
                  l10n.preparingCacheCount(cached),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
              if (pool != null)
                Text(
                  l10n.preparingSwapToday(swappedCount, pool),
                  textAlign: TextAlign.center,
                ),
              Text(
                dailySwapLine(l10n, percent: percent, poolSize: pool),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
