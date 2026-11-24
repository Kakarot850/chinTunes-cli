import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../ui/collection/collection_screen.dart';
import '../../ui/downloads/downloads_screen.dart';
import '../../ui/home/home_screen.dart';
import '../../ui/settings/settings_screen.dart';
import '../../ui/youtube/youtube_library_screen.dart';
import '../../ui/library/liked_screen.dart';
import '../../ui/library/library_screen.dart';
import '../../ui/library/playlist_screen.dart';
import '../../ui/player/now_playing_screen.dart';
import '../../ui/search/search_screen.dart';
import '../../ui/shell/app_shell.dart';
import '../../ui/widgets/state_views.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final routerProvider = Provider<GoRouter>((ref) => buildRouter());

GoRoute _collectionRoute() => GoRoute(
      path: 'collection',
      builder: (context, state) {
        final extra = state.extra;
        if (extra is CollectionSummary) return CollectionScreen(summary: extra);
        return const Scaffold(body: EmptyView(icon: Icons.link_off_rounded, title: 'This page is no longer available'));
      },
    );

GoRouter buildRouter() => GoRouter(
      navigatorKey: _rootKey,
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
                routes: [_collectionRoute()],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const SearchScreen(),
                routes: [_collectionRoute()],
              ),
            ]),
            StatefulShellBranch(routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
                routes: [
                  _collectionRoute(),
                  GoRoute(path: 'liked', builder: (context, state) => const LikedScreen()),
                  GoRoute(path: 'downloads', builder: (context, state) => const DownloadsScreen()),
                  GoRoute(
                    path: 'youtube',
                    builder: (context, state) => const YouTubeLibraryScreen(),
                    routes: [
                      GoRoute(
                        path: 'playlist',
                        builder: (context, state) {
                          final extra = state.extra;
                          if (extra is CollectionSummary) return AccountPlaylistScreen(summary: extra);
                          return const Scaffold(
                            body: EmptyView(icon: Icons.link_off_rounded, title: 'This page is no longer available'),
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'playlist/:id',
                    builder: (context, state) => PlaylistScreen(playlistId: state.pathParameters['id'] ?? ''),
                  ),
                ],
              ),
            ]),
          ],
        ),
        GoRoute(
          path: '/settings',
          parentNavigatorKey: _rootKey,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/player',
          parentNavigatorKey: _rootKey,
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: const NowPlayingScreen(),
            transitionDuration: const Duration(milliseconds: 320),
            reverseTransitionDuration: const Duration(milliseconds: 240),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
                child: child,
              );
            },
          ),
        ),
      ],
    );

/// Pushes a collection page inside the current tab's navigator.
void openCollection(BuildContext context, CollectionSummary summary) {
  final path = GoRouterState.of(context).uri.path;
  final base = path.startsWith('/search')
      ? '/search'
      : path.startsWith('/library')
          ? '/library'
          : '/home';
  context.push('$base/collection', extra: summary);
}
