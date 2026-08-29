import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../slideshow/domain/night_schedule.dart';
import '../state/settings_providers.dart';

class NightModeSettingsScreen extends ConsumerWidget {
  const NightModeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Nachtmodus')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) {
          final schedule = settings.nightSchedule;
          return RadioGroup<NightScheduleMode>(
            groupValue: schedule.mode,
            onChanged: (v) => notifier.updateSettings(
              (s) => s.copyWith(nightSchedule: schedule.copyWith(mode: v)),
            ),
            child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const RadioListTile<NightScheduleMode>(
                title: Text('Aus'),
                value: NightScheduleMode.disabled,
              ),
              const RadioListTile<NightScheduleMode>(
                title: Text('Feste Zeitspanne'),
                value: NightScheduleMode.fixedRange,
              ),
              const RadioListTile<NightScheduleMode>(
                title: Text('Sonnenauf-/-untergang'),
                subtitle: Text(
                  'Näherung ohne Standortdaten (20:00-07:00) - genaue '
                  'Berechnung folgt, sobald Standortfreigabe existiert',
                ),
                value: NightScheduleMode.sunsetSunrise,
              ),
              if (schedule.mode == NightScheduleMode.fixedRange) ...[
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start'),
                  trailing: Text(_formatTime(schedule.startHour, schedule.startMinute)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          TimeOfDay(hour: schedule.startHour, minute: schedule.startMinute),
                    );
                    if (picked != null) {
                      await notifier.updateSettings((s) => s.copyWith(
                            nightSchedule: schedule.copyWith(
                              startHour: picked.hour,
                              startMinute: picked.minute,
                            ),
                          ));
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ende'),
                  trailing: Text(_formatTime(schedule.endHour, schedule.endMinute)),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime:
                          TimeOfDay(hour: schedule.endHour, minute: schedule.endMinute),
                    );
                    if (picked != null) {
                      await notifier.updateSettings((s) => s.copyWith(
                            nightSchedule: schedule.copyWith(
                              endHour: picked.hour,
                              endMinute: picked.minute,
                            ),
                          ));
                    }
                  },
                ),
              ],
              const Divider(height: 32),
              Text('Dimm-Stärke: ${(schedule.dimAmount * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium),
              Slider(
                value: schedule.dimAmount,
                onChanged: schedule.mode == NightScheduleMode.disabled
                    ? null
                    : (v) => notifier.updateSettings(
                          (s) => s.copyWith(
                              nightSchedule: schedule.copyWith(dimAmount: v)),
                        ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  static String _formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
