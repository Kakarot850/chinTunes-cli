import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/playback_actions.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';
import '../collection/collection_screen.dart';
import '../widgets/collection_card.dart';
import '../widgets/state_views.dart';
import '../widgets/track_tile.dart';

/// Debounced multi-source search (JioSaavn + YouTube) with filter chips,
/// recent searches and share-link resolution (CLI "Download Any Link").
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _debounce = Duration(milliseconds: 350);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  String _query = '';
  SearchFilter _filter = SearchFilter.songs;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _setQuery(String value) {
    _timer?.cancel();
    _controller.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    setState(() => _query = value.trim());
  }

  /// Saves the query once the user acts on a result (or submits).
  void _commit() => unawaited(ref.read(libraryStoreProvider).addSearch(_query));

  @override
  Widget build(BuildContext context) {
    final isLink = _query.isNotEmpty && LinkRouter.looksLikeUrl(_query);
    // Albums / playlists / artists come from JioSaavn only.
    final youtubeOnly = ref.watch(musicSourceProvider) == MusicSource.youtube;
    final filter = youtubeOnly ? SearchFilter.songs : _filter;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        toolbarHeight: 72,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _setQuery(v);
            _commit();
          },
          decoration: InputDecoration(
            hintText: youtubeOnly ? 'Search YouTube or paste a link' : 'Songs, albums, artists or a link',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _setQuery('');
                      _focus.requestFocus();
                    },
                  ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_query.isNotEmpty && !isLink && !youtubeOnly)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final f in SearchFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(switch (f) {
                          SearchFilter.songs => 'Songs',
                          SearchFilter.collections => 'Albums & Playlists',
                          SearchFilter.artists => 'Artists',
                        }),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: _query.isEmpty
                ? _RecentSearches(onPick: _setQuery)
                : isLink
                    ? _LinkResult(url: _query, onUsed: _commit)
                    : _Results(query: _query, filter: filter, onUsed: _commit),
          ),
        ],
      ),
    );
  }
}

class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider).valueOrNull ?? const <String>[];
    final store = ref.read(libraryStoreProvider);
    if (recent.isEmpty) {
      return const EmptyView(
        icon: Icons.travel_explore_rounded,
        title: 'Find something to play',
        message: 'Search JioSaavn and YouTube, or paste a JioSaavn, YouTube or Spotify link.',
      );
    }
    return ListView.builder(
      itemCount: recent.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return SectionHeader(
            'Recent searches',
            trailing: TextButton(
              onPressed: () => unawaited(store.clearSearches()),
              child: const Text('Clear all'),
            ),
          );
        }
        final q = recent[i - 1];
        return ListTile(
          leading: const Icon(Icons.history_rounded),
          title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => onPick(q),
          trailing: IconButton(
            tooltip: 'Remove "$q" from recent searches',
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => unawaited(store.removeSearch(q)),
          ),
        );
      },
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.filter, required this.onUsed});

  final String query;
  final SearchFilter filter;
  final VoidCallback onUsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchResultsProvider((query, filter)));
    final bottom = MediaQuery.paddingOf(context).bottom + 24;

    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        title: 'Search failed',
        onRetry: () => ref.invalidate(searchResultsProvider((query, filter))),
      ),
      data: (r) {
        if (r.isEmpty) {
          return EmptyView(
            icon: Icons.search_off_rounded,
            title: 'No results for "$query"',
            message: r.errors.isEmpty ? 'Try a different spelling or fewer words.' : 'Some sources are unreachable right now.',
          );
        }
        if (filter == SearchFilter.songs) {
          // Flattened rows: section header (String) or Track.
          final rows = <Object>[
            if (r.songs.isNotEmpty) ...['JioSaavn', ...r.songs],
            if (r.youtube.isNotEmpty) ...['YouTube', ...r.youtube],
          ];
          return ListView.builder(
            padding: EdgeInsets.only(bottom: bottom),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is String) return SectionHeader(row);
              final track = row as Track;
              final list = track.source == TrackSource.youtube ? r.youtube : r.songs;
              return TrackTile(
                track: track,
                onTap: () {
                  onUsed();
                  ref.playQueue(list, index: list.indexOf(track));
                },
              );
            },
          );
        }
        final items = filter == SearchFilter.artists ? r.artists : r.collections;
        return ListView.builder(
          padding: EdgeInsets.only(bottom: bottom),
          itemCount: items.length,
          itemBuilder: (context, i) => CollectionTile(
            summary: items[i],
            onTap: () {
              onUsed();
              openCollection(context, items[i]);
            },
          ),
        );
      },
    );
  }
}

class _LinkResult extends ConsumerWidget {
  const _LinkResult({required this.url, required this.onUsed});

  final String url;
  final VoidCallback onUsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = LinkRouter.parse(url);
    if (target == null) {
      return const EmptyView(
        icon: Icons.link_off_rounded,
        title: 'This link isn\'t supported yet',
        message: 'Paste a JioSaavn song/album/playlist/artist, YouTube video/playlist, or Spotify track link.',
      );
    }
    final async = ref.watch(linkProvider(url));
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(
        title: 'Couldn\'t open this link',
        onRetry: () => ref.invalidate(linkProvider(url)),
      ),
      data: (col) => NotificationListener<ScrollStartNotification>(
        onNotification: (_) {
          onUsed();
          return false;
        },
        child: DecoratedBox(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: CollectionBody(collection: col),
        ),
      ),
    );
  }
}
