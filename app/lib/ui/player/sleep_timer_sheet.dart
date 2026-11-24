import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

Future<void> showSleepTimerSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => const _SleepTimerSheet(),
    );

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  static const _options = [15, 30, 45, 60];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);
    final theme = Theme.of(context);

    String? status;
    if (state.endOfTrack) {
      status = 'Stops at the end of this track';
    } else if (state.endsAt != null) {
      final t = TimeOfDay.fromDateTime(state.endsAt!);
      status = 'Stops at ${t.format(context)}';
    }

    void pick(VoidCallback action) {
      action();
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Sleep timer', style: theme.textTheme.titleLarge),
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(status, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.accent)),
            ),
          for (final m in _options)
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$m minutes'),
              onTap: () => pick(() => notifier.start(Duration(minutes: m))),
            ),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('End of track'),
            onTap: () => pick(notifier.endOfTrack),
          ),
          if (state.isActive)
            ListTile(
              leading: const Icon(Icons.timer_off_outlined),
              title: const Text('Turn off timer'),
              onTap: () => pick(notifier.cancel),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
