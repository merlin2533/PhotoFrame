import '../../../l10n/app_localizations.dart';
import '../domain/rotation_swap.dart';

/// The daily swap line shared by the home screen and the preparing view:
/// "Täglicher Austausch: P %", with "(N Fotos pro Tag)" when the size of the
/// rotation pool [poolSize] is known. N is the number of photos the swap
/// replaces per day (see [rotationSwapSize]), so 0 percent gives "0 Fotos".
String dailySwapLine(AppLocalizations l10n,
    {required int percent, int? poolSize}) {
  if (poolSize == null) return l10n.preparingSwapDailyPercent(percent);
  return l10n.preparingSwapDailyCount(
    percent,
    rotationSwapSize(poolSize, percent: percent),
  );
}
