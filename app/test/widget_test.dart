import 'package:chintunes/core/theme/app_colors.dart';
import 'package:chintunes/data/providers.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chintunes/core/theme/app_theme.dart';
import 'package:chintunes/core/utils/format.dart';
import 'package:chintunes/ui/widgets/artwork.dart';
import 'package:chintunes/ui/widgets/seek_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('theme', () {
    test('uses the OLED surface hierarchy', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF09090B));
      expect(AppColors.surface, const Color(0xFF121216));
      expect(AppColors.elevated, const Color(0xFF1C1C22));
      expect(AppColors.border, const Color(0x14FFFFFF));
      expect(theme.colorScheme.primary, AppColors.accent);
    });
  });

  group('formatDuration', () {
    test('formats m:ss and h:mm:ss', () {
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(minutes: 4, seconds: 22)), '4:22');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(formatDuration(null), '0:00');
    });

    test('pluralize', () {
      expect(pluralize(1, 'song'), '1 song');
      expect(pluralize(3, 'song'), '3 songs');
    });
  });

  group('SeekBarView', () {
    testWidgets('shows position and duration, reports seeks', (tester) async {
      Duration? seeked;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SeekBarView(
            position: const Duration(seconds: 65),
            duration: const Duration(minutes: 4, seconds: 22),
            onSeek: (d) => seeked = d,
          ),
        ),
      ));

      expect(find.text('1:05'), findsOneWidget);
      expect(find.text('4:22'), findsOneWidget);

      await tester.tap(find.byType(Slider));
      await tester.pumpAndSettle();
      expect(seeked, isNotNull);
      expect(seeked! > Duration.zero, isTrue);
    });

    testWidgets('is disabled when duration is unknown', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SeekBarView(position: Duration.zero, duration: null, onSeek: (_) {}),
        ),
      ));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });
  });

  testWidgets('Artwork shows a placeholder without a url', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [dataModeProvider.overrideWithValue(DataMode.high)],
      child: const MaterialApp(home: Scaffold(body: Artwork(url: null, size: 48))),
    ));
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  group('formatters', () {
    test('formatBytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2 KB');
      expect(formatBytes(4404019), '4.2 MB');
    });

    test('formatRelative', () {
      final now = DateTime(2026, 11, 24, 12);
      expect(formatRelative(now.subtract(const Duration(seconds: 20)), now: now), 'just now');
      expect(formatRelative(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
      expect(formatRelative(now.subtract(const Duration(days: 2)), now: now), '2 d ago');
    });
  });
}
