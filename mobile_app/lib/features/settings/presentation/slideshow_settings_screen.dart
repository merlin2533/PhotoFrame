import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../slideshow/domain/slideshow_config.dart';
import '../domain/app_settings.dart';
import '../state/settings_providers.dart';

class SlideshowSettingsScreen extends ConsumerWidget {
  const SlideshowSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsSlideshowTitle)),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.commonError('$e'))),
        data: (settings) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l10n.slideshowSettingsInterval(settings.intervalSeconds),
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.intervalSeconds.toDouble(),
              min: 3,
              max: 120,
              divisions: 117,
              label:
                  l10n.slideshowSettingsIntervalValue(settings.intervalSeconds),
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(intervalSeconds: v.round())),
            ),
            Text(l10n.rotationSwapPercentLabel(settings.rotationSwapPercent),
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.rotationSwapPercent.toDouble(),
              min: 0,
              max: 50,
              divisions: 10,
              label: '${settings.rotationSwapPercent} %',
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(rotationSwapPercent: v.round())),
            ),
            Text(l10n.rotationRenewalDaysLabel(settings.rotationRenewalDays),
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: settings.rotationRenewalDays.toDouble(),
              min: 1,
              max: 30,
              divisions: 29,
              label: '${settings.rotationRenewalDays}',
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(rotationRenewalDays: v.round())),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.smallPhotoPreparationTitle),
              subtitle: Text(l10n.smallPhotoPreparationSubtitle),
              value: settings.smallPhotoPreparation,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(smallPhotoPreparation: v)),
            ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsOverlays,
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsShowSourceLabel),
              value: settings.showSourceLabel,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(showSourceLabel: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsShowCaption),
              subtitle: Text(l10n.slideshowSettingsShowCaptionSubtitle),
              value: settings.showCaptionOverlay,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(showCaptionOverlay: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsShowClock),
              value: settings.showClock,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(showClock: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsClockAtTop),
              subtitle: Text(l10n.slideshowSettingsClockAtTopSubtitle),
              value: settings.clockAtTop,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(clockAtTop: v)),
            ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsDisplayMode,
                style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<DisplayMode>(
              groupValue: settings.displayMode,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(displayMode: v)),
              child: Column(
                children: [
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsDisplayContain),
                    value: DisplayMode.contain,
                  ),
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsDisplayCover),
                    value: DisplayMode.cover,
                  ),
                  RadioListTile<DisplayMode>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsDisplayBlurred),
                    subtitle:
                        Text(l10n.slideshowSettingsDisplayBlurredSubtitle),
                    value: DisplayMode.blurredBackdrop,
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsTransitions,
                style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<SlideshowTransition>(
              groupValue: settings.transition,
              onChanged: (v) =>
                  notifier.updateSettings((s) => s.copyWith(transition: v)),
              child: Column(
                children: [
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransFade),
                    value: SlideshowTransition.fade,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransSlide),
                    value: SlideshowTransition.slide,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransZoom),
                    value: SlideshowTransition.zoom,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransSlideUp),
                    value: SlideshowTransition.slideUp,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransBlur),
                    value: SlideshowTransition.blurFade,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransFlip),
                    value: SlideshowTransition.flip,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransRandom),
                    value: SlideshowTransition.random,
                  ),
                  RadioListTile<SlideshowTransition>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.slideshowSettingsTransNone),
                    value: SlideshowTransition.none,
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsKenBurns),
              subtitle: Text(l10n.slideshowSettingsKenBurnsSubtitle),
              value: settings.kenBurnsEnabled,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(kenBurnsEnabled: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsPortraitPair),
              subtitle: Text(l10n.slideshowSettingsPortraitPairSubtitle),
              value: settings.portraitPairLayoutEnabled,
              onChanged: (v) => notifier.updateSettings(
                  (s) => s.copyWith(portraitPairLayoutEnabled: v)),
            ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsLayout,
                style: Theme.of(context).textTheme.titleMedium),
            SegmentedButton<SlideLayout>(
              segments: [
                ButtonSegment(
                    value: SlideLayout.single,
                    label: Text(l10n.slideshowSettingsLayoutSingle)),
                ButtonSegment(
                    value: SlideLayout.grid2x2,
                    label: Text(l10n.slideshowSettingsLayoutGrid)),
              ],
              selected: {settings.slideLayout},
              onSelectionChanged: (sel) => notifier
                  .updateSettings((s) => s.copyWith(slideLayout: sel.first)),
            ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsImageDetails,
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsImageDetailsSwitch),
              subtitle: Text(l10n.slideshowSettingsImageDetailsSubtitle),
              value: settings.showImageDetails,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(showImageDetails: v)),
            ),
            if (settings.showImageDetails)
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                      value: false,
                      label: Text(l10n.slideshowSettingsLeft),
                      icon: const Icon(Icons.align_horizontal_left)),
                  ButtonSegment(
                      value: true,
                      label: Text(l10n.slideshowSettingsRight),
                      icon: const Icon(Icons.align_horizontal_right)),
                ],
                selected: {settings.imageDetailsOnRight},
                onSelectionChanged: (sel) => notifier.updateSettings(
                    (s) => s.copyWith(imageDetailsOnRight: sel.first)),
              ),
            const Divider(height: 32),
            Text(l10n.slideshowSettingsFavoritesAndDate,
                style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsFavoritesOnly),
              subtitle: Text(l10n.slideshowSettingsFavoritesOnlySubtitle),
              value: settings.favoritesOnlyMode,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(favoritesOnlyMode: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.slideshowSettingsOnThisDay),
              subtitle: Text(l10n.slideshowSettingsOnThisDaySubtitle),
              value: settings.preferOnThisDayEnabled,
              onChanged: (v) => notifier
                  .updateSettings((s) => s.copyWith(preferOnThisDayEnabled: v)),
            ),
          ],
        ),
      ),
    );
  }
}
