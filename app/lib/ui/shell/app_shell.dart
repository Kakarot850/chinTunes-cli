import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../player/mini_player.dart';

/// Tab shell: content scrolls under a blurred dock holding the mini-player
/// and the navigation bar (`extendBody`, so lists get bottom padding from
/// `MediaQuery.paddingOf(context).bottom`).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _errorSub = ref.read(audioHandlerProvider).errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    unawaited(_errorSub?.cancel());
    super.dispose();
  }

  bool _confirming = false;

  /// System back at the root of a tab: other tabs → Home; Home → confirm exit.
  /// (Back inside a tab's stack or on /player is handled by go_router first.)
  Future<void> _onRootBack() async {
    final shell = widget.navigationShell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    if (_confirming) return;
    _confirming = true;
    final playing = ref.read(isPlayingProvider);
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Exit chinTunes?'),
        content: Text(playing ? 'Playback will stop.' : 'You can come back any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Exit')),
        ],
      ),
    );
    _confirming = false;
    if (exit != true) return;
    await ref.read(audioHandlerProvider).stop();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onRootBack());
      },
      child: Scaffold(
      extendBody: true,
      body: shell,
      // No BackdropFilter: a full-width blur re-rendered on every scroll frame
      // and every 200 ms progress tick, which made lists stutter (B-033).
      bottomNavigationBar: RepaintBoundary(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Color(0xF51C1C22), // AppColors.elevated at 96%
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MiniPlayer(),
                NavigationBar(
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      selectedIcon: Icon(Icons.manage_search_rounded),
                      label: 'Search',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.library_music_outlined),
                      selectedIcon: Icon(Icons.library_music_rounded),
                      label: 'Library',
                    ),
                  ],
                ),
              ],
            ),
          ),
      ),
      ),
    );
  }
}
