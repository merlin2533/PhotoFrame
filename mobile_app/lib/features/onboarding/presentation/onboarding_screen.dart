import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../../../l10n/app_localizations.dart';
import '../../settings/state/settings_providers.dart';

/// First-run setup wizard.
///
/// Explains what the app does, what "Dauer-Modus" (always-on display)
/// costs in terms of battery, and how to set the device up as a dedicated
/// photo frame (home-app/launcher + battery-optimization allowlist on
/// Android, "Guided Access" on iOS). Persisted via
/// `AppSettings.onboardingCompleted` so it only auto-shows once; reachable
/// again any time from Settings -> "Setup-Guide erneut anzeigen".
///
/// Design decision: rather than adding `android_intent_plus` (a native
/// platform-channel plugin) just to deep-link into the exact
/// "default apps -> home app" settings page, this screen uses the
/// `permission_handler` package (already a dependency) to open the app's
/// general settings page via `openAppSettings()`. That is not the precise
/// screen for choosing a home-app launcher, but it gets the user into
/// Android Settings in one tap without adding a new, less-maintained native
/// dependency for a single button; the accompanying text explains the exact
/// manual path ("Settings -> Apps -> Default apps -> Home app").
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const int _pageCount = 7;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish({required bool goToSources}) async {
    await ref.read(settingsProvider.notifier).markOnboardingCompleted();
    if (!mounted) return;
    if (goToSources) {
      context.go('/settings/sources/add');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLast = _page == _pageCount - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_page + 1) / _pageCount,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _finish(goToSources: false),
                    child: Text(l10n.onboardingSkip),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (p) => setState(() => _page = p),
                children: const [
                  _WelcomeStep(),
                  _AlwaysOnExplainerStep(),
                  _AndroidHomeAppStep(),
                  _AndroidBatteryOptimizationStep(),
                  _OemAutostartHintsStep(),
                  _IosGuidedAccessStep(),
                  _AddSourceStep(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Row(
                children: [
                  if (_page > 0)
                    OutlinedButton(
                      onPressed: () => _goToPage(_page - 1),
                      child: Text(l10n.commonBack),
                    )
                  else
                    const SizedBox.shrink(),
                  const Spacer(),
                  FilledButton(
                    onPressed: isLast
                        ? () => _finish(goToSources: true)
                        : () => _goToPage(_page + 1),
                    child: Text(isLast ? l10n.onboardingAddSourceCta : l10n.commonNext),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.icon,
    required this.title,
    required this.body,
    this.extra,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          body,
          if (extra != null) ...[
            const SizedBox(height: 20),
            extra!,
          ],
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepScaffold(
      icon: Icons.photo_library_outlined,
      title: l10n.onboardingWelcomeTitle,
      body: Text(l10n.onboardingWelcomeBody),
    );
  }
}

class _AlwaysOnExplainerStep extends StatelessWidget {
  const _AlwaysOnExplainerStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepScaffold(
      icon: Icons.brightness_high_outlined,
      title: l10n.onboardingAlwaysOnTitle,
      body: Text(l10n.onboardingAlwaysOnBody),
      extra: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.onboardingAlwaysOnRecommendation,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidHomeAppStep extends StatelessWidget {
  const _AndroidHomeAppStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_isAndroid) {
      return _StepScaffold(
        icon: Icons.android,
        title: l10n.onboardingAndroidHomeAppTitle,
        body: Text(l10n.onboardingAndroidOnlyStepBody),
      );
    }
    return _StepScaffold(
      icon: Icons.android,
      title: l10n.onboardingAndroidHomeAppTitle,
      body: Text(l10n.onboardingAndroidHomeAppBody),
      extra: FilledButton.tonalIcon(
        onPressed: () => unawaited(ph.openAppSettings()),
        icon: const Icon(Icons.settings),
        label: Text(l10n.onboardingOpenAndroidSettings),
      ),
    );
  }
}

class _AndroidBatteryOptimizationStep extends StatelessWidget {
  const _AndroidBatteryOptimizationStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_isAndroid) {
      return _StepScaffold(
        icon: Icons.battery_charging_full_outlined,
        title: l10n.onboardingBatteryOptTitle,
        body: Text(l10n.onboardingAndroidOnlyStepBody),
      );
    }
    return _StepScaffold(
      icon: Icons.battery_charging_full_outlined,
      title: l10n.onboardingBatteryOptTitle,
      body: Text(l10n.onboardingBatteryOptBody),
      extra: FilledButton.tonalIcon(
        onPressed: () => unawaited(ph.openAppSettings()),
        icon: const Icon(Icons.settings),
        label: Text(l10n.onboardingOpenAppSettings),
      ),
    );
  }
}

/// OEM-specific autostart/battery-whitelist hints (Task 5). Pure text, no
/// vendor-specific settings deep links - see `autostart_help_screen.dart`
/// doc comment for why. Skipped (shown as N/A) on non-Android platforms,
/// same pattern as the other Android-only steps in this wizard.
class _OemAutostartHintsStep extends StatelessWidget {
  const _OemAutostartHintsStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!_isAndroid) {
      return _StepScaffold(
        icon: Icons.phonelink_setup_outlined,
        title: l10n.onboardingAutostartHintsTitle,
        body: Text(l10n.onboardingAndroidOnlyStepBody),
      );
    }
    return _StepScaffold(
      icon: Icons.phonelink_setup_outlined,
      title: l10n.onboardingAutostartHintsTitle,
      body: Text(l10n.onboardingAutostartHintsIntro),
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ${l10n.onboardingAutostartXiaomi}'),
          const SizedBox(height: 8),
          Text('•  ${l10n.onboardingAutostartHuawei}'),
          const SizedBox(height: 8),
          Text('•  ${l10n.onboardingAutostartSamsung}'),
          const SizedBox(height: 8),
          Text('•  ${l10n.onboardingAutostartOnePlusOppoVivo}'),
          const SizedBox(height: 12),
          Text(
            l10n.onboardingAutostartOutro,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _IosGuidedAccessStep extends StatelessWidget {
  const _IosGuidedAccessStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepScaffold(
      icon: Icons.lock_clock_outlined,
      title: l10n.onboardingIosGuidedAccessTitle,
      body: Text(l10n.onboardingIosGuidedAccessBody),
    );
  }
}

class _AddSourceStep extends StatelessWidget {
  const _AddSourceStep();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _StepScaffold(
      icon: Icons.add_photo_alternate_outlined,
      title: l10n.onboardingAddSourceTitle,
      body: Text(l10n.onboardingAddSourceBody),
    );
  }
}

bool get _isAndroid {
  try {
    return Platform.isAndroid;
  } catch (_) {
    // Platform is unavailable on web/some test hosts.
    return false;
  }
}
