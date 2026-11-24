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

  static const Duration _exitWindow = Duration(seconds: 2);
  DateTime? _lastBack;

  /// System back at the root of a tab: other tabs → Home. On Home, the first
  /// back shows a hint and a second back within 2 s closes the app. Playback
  /// is NOT stopped: the audio_service foreground service keeps playing and
  /// the notification brings the app back (B-034 revised).
  void _onRootBack() {
    final shell = widget.navigationShell;
    if (shell.currentIndex != 0) {
      shell.goBranch(0);
      return;
    }
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) < _exitWindow) {
      _lastBack = null;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      unawaited(SystemNavigator.pop());
      return;
    }
    _lastBack = now;
    final playing = ref.read(isPlayingProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: _exitWindow,
        content: Text(playing ? 'Press back again to exit. Music keeps playing.' : 'Press back again to exit.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.navigationShell;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onRootBack();
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
