import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../widgets/state_views.dart';
import '../youtube/takeout_import.dart';
import '../youtube/youtube_library_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final cache = ref.read(audioCacheProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear the stream cache?'),
        content: const Text('Cached songs will stream again the next time you play them. Downloads are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Clear cache')),
        ],
      ),
    );
    if (ok != true) return;
    await cache.clear();
    ref.invalidate(storageUsageProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(dataModeProvider);
    final usage = ref.watch(dataUsageProvider).valueOrNull ?? const DataUsageSnapshot();
    final storage = ref.watch(storageUsageProvider).valueOrNull;
    final network = ref.watch(networkKindProvider).valueOrNull ?? NetworkKind.wifi;
    final theme = Theme.of(context);
    String mb(int bytes) => '${DataUsageSnapshot.mb(bytes).toStringAsFixed(1)} MB';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 24),
        children: [
          const SectionHeader('Data mode'),
          for (final m in DataMode.values)
            ListTile(
              selected: m == mode,
              selectedColor: AppColors.textPrimary,
              leading: Icon(
                m == mode ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: m == mode ? AppColors.accent : AppColors.textTertiary,
              ),
              title: Text(m.label),
              subtitle: Text(m.description),
              onTap: () => unawaited(ref.read(dataModeNotifierProvider.notifier).set(m)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              switch (network) {
                NetworkKind.cellular when mode == DataMode.ultraSaver =>
                  'On mobile data: the next song loads when it starts (no prefetch).',
                NetworkKind.cellular => 'On mobile data.',
                NetworkKind.offline => 'Offline: only downloads and cached songs play.',
                _ => 'On Wi-Fi.',
              },
              style: theme.textTheme.bodySmall,
            ),
          ),
          const SectionHeader('Data saved'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: _Stat(label: 'This session', value: mb(usage.sessionSavedBytes))),
                const SizedBox(width: 12),
                Expanded(child: _Stat(label: 'All time', value: mb(usage.totalSavedBytes))),
                const SizedBox(width: 12),
                Expanded(child: _Stat(label: 'Streamed', value: mb(usage.totalUsedBytes))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Compared with High quality. Downloads and cached replays count as fully saved.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () => ref.read(coreServicesProvider).usage.resetTotals(),
                child: const Text('Reset counters'),
              ),
            ),
          ),
          const SectionHeader('Storage'),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Downloads'),
            subtitle: Text(storage == null ? 'Calculating…' : formatBytes(storage.downloads)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.go('/library/downloads'),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.save_alt_rounded),
            title: const Text('Cache songs while streaming'),
            subtitle: const Text('Replays use no data. Turn off if scrolling stutters during playback.'),
            value: ref.watch(streamCacheProvider),
            onChanged: (v) => unawaited(ref.read(streamCacheProvider.notifier).set(v)),
          ),
          ListTile(
            leading: const Icon(Icons.cached_rounded),
            title: const Text('Stream cache'),
            subtitle: Text(
              storage == null
                  ? 'Calculating…'
                  : '${formatBytes(storage.cache)} · replays and seeking use no data',
            ),
            trailing: TextButton(
              onPressed: () => unawaited(_clearCache(context, ref)),
              child: const Text('Clear cache'),
            ),
          ),
          const SectionHeader('Account & history'),
          const AccountTile(),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import Google Takeout history'),
            subtitle: const Text('watch-history.json from takeout.google.com'),
            onTap: () => unawaited(importTakeoutHistory(context, ref)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(label, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
