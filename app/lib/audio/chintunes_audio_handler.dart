import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:chintunes_core/chintunes_core.dart';
import 'package:just_audio/just_audio.dart';

import '../data/audio_cache.dart';

typedef TrackCallback = void Function(Track track);

/// A source ready for just_audio plus what we need for badges / accounting.
class _Prepared {
  const _Prepared({required this.source, required this.badge, required this.fromLocal, this.kbps});

  final AudioSource source;
  final String badge;
  final bool fromLocal;
  final int? kbps;
}

/// Background audio engine (audio_service + just_audio).
///
/// Streams are resolved lazily. The player holds a 1–2 item
/// [ConcatenatingAudioSource] window `[current, prefetchedNext]`: auto-advance
/// into the prefetched child is gapless; the handler then drops child 0 and
/// prefetches the following track. Manual skips / queue edits rebuild it.
///
/// Source priority per track (zero network for 1 and 2):
/// 1. offline download (`localize` / resolver offline lookup) → file
/// 2. complete stream-cache file → file
/// 3. network stream in the current [DataMode], wrapped in
///    [LockCachingAudioSource] so replays and scrubbing are served from disk.
///
/// Endless radio: while a [MixSession] is active, the queue is refilled
/// whenever ≤ 3 tracks remain.
class ChinTunesAudioHandler extends BaseAudioHandler with SeekHandler {
  ChinTunesAudioHandler({
    required StreamResolver resolver,
    this.onTrackStarted,
    Track Function(Track track)? localize,
    AudioCache? cache,
    bool Function()? allowPrefetch,
    DataUsageMeter? usage,
  })  : _resolver = resolver,
        _localize = localize ?? ((t) => t),
        _cache = cache,
        _allowPrefetch = allowPrefetch ?? (() => true),
        _usage = usage {
    _subs.addAll([
      _player.playbackEventStream.listen((_) => _broadcastState(), onError: _onPlayerError),
      _player.playingStream.listen((_) => _broadcastState()),
      _player.currentIndexStream.listen(_onPlayerIndexChanged),
      _player.durationStream.listen(_onDuration),
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) unawaited(_onCompleted());
      }),
      positionStream.listen((p) {
        if (p > _maxPosition) _maxPosition = p;
      }),
    ]);
    unawaited(_initSession());
  }

  final StreamResolver _resolver;
  final TrackCallback? onTrackStarted;
  final Track Function(Track track) _localize;
  final AudioCache? _cache;
  final bool Function() _allowPrefetch;
  final DataUsageMeter? _usage;

  final AudioPlayer _player = AudioPlayer();
  final PlaybackQueue _queue = PlaybackQueue();
  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<String> _errors = StreamController<String>.broadcast();
  final StreamController<void> _sleepFired = StreamController<void>.broadcast();

  ConcatenatingAudioSource? _source;
  Track? _prefetchedTrack;
  _Prepared? _prefetched;
  _Prepared? _current;
  Track? _currentTrackForUsage;
  Duration _maxPosition = Duration.zero;
  RepeatMode _repeat = RepeatMode.off;
  bool _loading = false;
  bool _pauseAtEndOfTrack = false;
  int _loadToken = 0;
  int _prefetchToken = 0;
  int _consecutiveErrors = 0;
  MixSession? _mix;
  bool _refilling = false;

  // ------------------------------------------------------------ public API

  /// Throttled to 200 ms so only the seek bar rebuilds on position ticks.
  late final Stream<Duration> positionStream = _player
      .createPositionStream(
        minPeriod: const Duration(milliseconds: 200),
        maxPeriod: const Duration(milliseconds: 200),
      )
      .asBroadcastStream();

  Stream<String> get errors => _errors.stream;
  Stream<void> get sleepFired => _sleepFired.stream;

  Track? get currentTrack => _queue.current;
  List<Track> get queueTracks => _queue.tracks;
  int get queueCurrentIndex => _queue.currentIndex;
  RepeatMode get repeat => _repeat;
  bool get shuffle => _queue.shuffle;
  String? get currentBadge => _current?.badge;
  bool get pauseAtEndOfTrack => _pauseAtEndOfTrack;
  DataMode get dataMode => _resolver.dataMode;

  /// Title of the running endless mix, or null.
  String? get mixTitle => _mix?.title;

  /// Applies a new Data Mode; affects the next stream that is resolved.
  Future<void> setDataMode(DataMode mode) async {
    _resolver.dataMode = mode;
    await refreshPrefetchPolicy();
  }

  /// Re-evaluates prefetch after a network / data-mode change.
  Future<void> refreshPrefetchPolicy() => _syncPrefetch();

  Future<void> playTracks(List<Track> tracks, {int startIndex = 0, bool? shuffle}) async {
    if (tracks.isEmpty) return;
    _mix = null;
    if (shuffle != null) _queue.setShuffle(shuffle);
    _queue.setTracks(tracks, startIndex: startIndex);
    _publishQueue();
    await _loadCurrent();
  }

  /// Plays [lead] (if any) followed by the mix, refilling endlessly.
  Future<void> startMix(MixSession session, {Track? lead}) async {
    if (lead != null) session.markSeen([lead]);
    final tracks = [if (lead != null) lead, ...session.initialTracks];
    if (tracks.isEmpty) return;
    _queue.setShuffle(false);
    _queue.setTracks(tracks);
    _mix = session;
    _publishQueue();
    await _loadCurrent();
  }

  Future<void> addToQueue(Track track) async {
    final wasEmpty = _queue.isEmpty;
    _queue.add(track);
    _publishQueue();
    if (wasEmpty) {
      await _loadCurrent();
    } else {
      await _syncPrefetch();
    }
  }

  Future<void> playNext(Track track) async {
    final wasEmpty = _queue.isEmpty;
    _queue.insertNext(track);
    _publishQueue();
    if (wasEmpty) {
      await _loadCurrent();
    } else {
      await _syncPrefetch();
    }
  }

  Future<void> moveQueueItem(int from, int to) async {
    _queue.move(from, to);
    _publishQueue();
    _broadcastState();
    await _syncPrefetch();
  }

  /// Pause when the current track ends (sleep timer "end of track").
  Future<void> setPauseAtEndOfTrack(bool enabled) async {
    _pauseAtEndOfTrack = enabled;
    await _syncPrefetch();
  }

  // ------------------------------------------------- AudioHandler overrides

  @override
  Future<void> play() async {
    if (_queue.current == null) return;
    if (_player.audioSource == null) {
      await _loadCurrent();
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    // just_audio's play() future only completes when playback stops.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _reportUsage();
    _loadToken++;
    _prefetchToken++;
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    final next = _queue.nextIndex(_repeat == RepeatMode.one ? RepeatMode.all : _repeat);
    if (next == null) return;
    final prefetched = _prefetchedTrack;
    if (prefetched != null && _queue.trackAt(next) == prefetched && _player.hasNext) {
      await _player.seekToNext(); // handled in _onPlayerIndexChanged
      if (!_player.playing) unawaited(_player.play());
      return;
    }
    _queue.moveTo(next);
    await _loadCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    // CLI parity: "previous" restarts the track after 3.5 s.
    if (_player.position > const Duration(milliseconds: 3500)) {
      await _player.seek(Duration.zero);
      return;
    }
    final prev = _queue.previousIndex(_repeat == RepeatMode.one ? RepeatMode.all : _repeat);
    if (prev == null) {
      await _player.seek(Duration.zero);
      return;
    }
    _queue.moveTo(prev);
    await _loadCurrent();
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.moveTo(index);
    await _loadCurrent();
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final removingCurrent = index == _queue.currentIndex;
    _queue.removeAt(index);
    _publishQueue();
    if (_queue.isEmpty) {
      await stop();
      mediaItem.add(null);
      return;
    }
    if (removingCurrent) {
      await _loadCurrent(autoplay: _player.playing);
    } else {
      _broadcastState();
      await _syncPrefetch();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    _queue.setShuffle(shuffleMode != AudioServiceShuffleMode.none);
    _broadcastState();
    await _syncPrefetch();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    _repeat = switch (repeatMode) {
      AudioServiceRepeatMode.none => RepeatMode.off,
      AudioServiceRepeatMode.one => RepeatMode.one,
      AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => RepeatMode.all,
    };
    await _player.setLoopMode(_repeat == RepeatMode.one ? LoopMode.one : LoopMode.off);
    _broadcastState();
    await _syncPrefetch();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Keep playing when swiped away mid-song; release the service otherwise.
    if (!_player.playing) await stop();
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _errors.close();
    await _sleepFired.close();
    await _player.dispose();
  }

  // -------------------------------------------------------------- internals

  Future<void> _initSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Headphones unplugged / BT disconnected → pause (Android "becoming noisy").
    _subs.add(session.becomingNoisyEventStream.listen((_) {
      unawaited(pause());
    }));
  }

  /// Builds the audio source for [original] (offline → cache → network).
  Future<_Prepared> _prepare(Track original) async {
    final track = _localize(original);
    final tag = _mediaItemFor(original);

    final cached = track.localPath == null ? _cache?.completeFor(track) : null;
    if (cached != null) {
      return _Prepared(source: AudioSource.file(cached.path, tag: tag), badge: 'Cached · 0 KB data', fromLocal: true);
    }

    final stream = await _resolver.resolve(track);
    if (stream.isLocal) {
      return _Prepared(
        source: AudioSource.file(stream.uri.toFilePath(), tag: tag),
        badge: 'Downloaded · ${stream.codec ?? 'offline'}',
        fromLocal: true,
        kbps: stream.bitrateKbps,
      );
    }

    // Headers are deliberately not forwarded (B-006): neither JioSaavn's CDN
    // nor googlevideo needs them.
    final cacheFile = _cache?.fileFor(original, _resolver.dataMode);
    final AudioSource source = cacheFile == null
        ? AudioSource.uri(stream.uri, tag: tag)
        : LockCachingAudioSource(stream.uri, cacheFile: cacheFile, tag: tag);
    return _Prepared(source: source, badge: stream.badge, fromLocal: false, kbps: stream.bitrateKbps);
  }

  void _startUsage(Track track, _Prepared prepared) {
    _currentTrackForUsage = track;
    _current = prepared;
    _maxPosition = Duration.zero;
  }

  /// Credits the outgoing track to the data-usage meter.
  void _reportUsage({Duration? listened}) {
    final track = _currentTrackForUsage;
    final info = _current;
    final meter = _usage;
    if (track == null || info == null || meter == null) return;
    meter.recordPlayback(
      actualKbps: info.kbps,
      baselineKbps: StreamSelector.highBaselineKbps(track),
      listened: listened ?? _maxPosition,
      fromLocal: info.fromLocal,
    );
    _currentTrackForUsage = null;
    _maxPosition = Duration.zero;
  }

  Future<void> _loadCurrent({bool autoplay = true, Duration? position}) async {
    final track = _queue.current;
    if (track == null) return;
    _reportUsage();
    final token = ++_loadToken;
    _prefetchToken++;
    _prefetchedTrack = null;
    _prefetched = null;
    _current = null;
    _loading = true;
    mediaItem.add(_mediaItemFor(track));
    _broadcastState();

    try {
      final prepared = await _prepare(track);
      if (token != _loadToken) return;
      final source = ConcatenatingAudioSource(children: [prepared.source]);
      _source = source;
      await _player.setAudioSource(source, initialPosition: position);
      if (token != _loadToken) return;

      _loading = false;
      _consecutiveErrors = 0;
      _startUsage(track, prepared);
      mediaItem.add(_mediaItemFor(track, badge: prepared.badge, duration: _player.duration));
      onTrackStarted?.call(track);
      _broadcastState();
      if (autoplay) unawaited(_player.play());
      unawaited(_prefetchNext());
      _maybeRefillMix();
    } catch (e) {
      if (token != _loadToken) return;
      _loading = false;
      await _handleFailure(track, e);
    }
  }

  Future<void> _handleFailure(Track track, Object error) async {
    _consecutiveErrors++;
    _errors.add('Couldn\'t play "${track.title}". ${_friendly(error)}');
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.error,
      errorMessage: error.toString(),
    ));
    // CLI parity: skip to the next track on failure, but stop after 3 in a row.
    if (_consecutiveErrors >= 3) return;
    final next = _queue.nextIndex(_repeat == RepeatMode.one ? RepeatMode.off : _repeat);
    if (next == null || next == _queue.currentIndex) return;
    _queue.moveTo(next);
    await _loadCurrent();
  }

  static String _friendly(Object error) {
    if (error is StreamResolveException) return 'No playable stream was found.';
    if (error is PlayerException) return 'The stream could not be opened.';
    return 'Check your connection and try again.';
  }

  void _onPlayerError(Object error, StackTrace stackTrace) {
    if (_loading) return; // load failures are handled by _loadCurrent
    final track = _queue.current;
    if (track != null) unawaited(_handleFailure(track, error));
  }

  bool get _prefetchAllowed =>
      _repeat != RepeatMode.one && !_pauseAtEndOfTrack && _allowPrefetch();

  Future<void> _prefetchNext() async {
    if (!_prefetchAllowed) return;
    final next = _queue.nextIndex(_repeat);
    if (next == null || next == _queue.currentIndex) return;
    final track = _queue.trackAt(next);
    final loadToken = _loadToken;
    final prefetchToken = ++_prefetchToken;
    try {
      final prepared = await _prepare(track);
      final source = _source;
      if (loadToken != _loadToken || prefetchToken != _prefetchToken || source == null) return;
      await source.add(prepared.source);
      if (loadToken != _loadToken || prefetchToken != _prefetchToken) return;
      _prefetchedTrack = track;
      _prefetched = prepared;
    } catch (_) {
      // Not fatal: _onCompleted loads the next track the slow way.
    }
  }

  /// Re-validates the prefetched child after queue / mode / network changes.
  Future<void> _syncPrefetch() async {
    final source = _source;
    if (source == null || _loading) return;
    final next = _queue.nextIndex(_repeat);
    final wanted = (next == null || !_prefetchAllowed) ? null : _queue.trackAt(next);
    if (wanted != null && wanted == _prefetchedTrack && source.length > 1) return;

    _prefetchToken++;
    _prefetchedTrack = null;
    _prefetched = null;
    if (source.length > 1) {
      await source.removeRange(1, source.length);
    }
    if (wanted != null) await _prefetchNext();
  }

  void _maybeRefillMix() {
    final mix = _mix;
    if (mix == null || _refilling) return;
    final order = _queue.order;
    final remaining = order.length - 1 - order.indexOf(_queue.currentIndex);
    if (remaining > 3) return;
    _refilling = true;
    unawaited(() async {
      try {
        final more = await mix.more();
        if (!identical(_mix, mix) || more.isEmpty) return;
        for (final t in more) {
          _queue.add(t);
        }
        _publishQueue();
        await _syncPrefetch();
      } catch (_) {
        // Offline / InnerTube hiccup: retried on the next track change.
      } finally {
        _refilling = false;
      }
    }());
  }

  void _onPlayerIndexChanged(int? index) {
    if (index == null || index == 0) return;
    final next = _prefetchedTrack;
    final prepared = _prefetched;
    if (next == null || prepared == null) return;
    // Gapless auto-advance: the previous track played to its end.
    final previousDuration = mediaItem.value?.duration;
    _reportUsage(listened: previousDuration == null ? null : _maxDuration(previousDuration));

    final nextIndex = _queue.nextIndex(_repeat == RepeatMode.one ? RepeatMode.all : _repeat);
    if (nextIndex != null && _queue.trackAt(nextIndex) == next) {
      _queue.moveTo(nextIndex);
    } else {
      final i = _queue.tracks.indexOf(next);
      if (i >= 0) _queue.moveTo(i);
    }
    _prefetchedTrack = null;
    _prefetched = null;
    final track = _queue.current;
    if (track != null) {
      _startUsage(track, prepared);
      mediaItem.add(_mediaItemFor(track, badge: prepared.badge, duration: _player.duration));
      onTrackStarted?.call(track);
    }
    _broadcastState();
    final source = _source;
    if (source != null) {
      unawaited(source.removeAt(0).then((_) => _prefetchNext()));
    }
    _maybeRefillMix();
  }

  Duration _maxDuration(Duration d) => _maxPosition > d ? _maxPosition : d;

  Future<void> _onCompleted() async {
    final duration = mediaItem.value?.duration;
    _reportUsage(listened: duration == null ? null : _maxDuration(duration));
    if (_pauseAtEndOfTrack) {
      _pauseAtEndOfTrack = false;
      _sleepFired.add(null);
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    final next = _queue.nextIndex(_repeat);
    if (next == null) {
      await _player.pause();
      await _player.seek(Duration.zero);
      return;
    }
    _queue.moveTo(next);
    await _loadCurrent();
  }

  void _onDuration(Duration? duration) {
    final item = mediaItem.value;
    if (item == null || duration == null || item.duration == duration) return;
    mediaItem.add(item.copyWith(duration: duration));
  }

  void _publishQueue() {
    // Indices must match PlaybackQueue (queue sheet / skipToQueueItem), so the
    // full queue is published even for long endless mixes.
    queue.add(_queue.tracks.map((t) => _mediaItemFor(t)).toList());
  }

  MediaItem _mediaItemFor(Track t, {String? badge, Duration? duration}) {
    final local = _localize(t);
    final art = ArtworkSizer.adapt(local.imageUrl, _resolver.dataMode);
    return MediaItem(
      id: t.uid,
      title: t.title,
      artist: t.artist,
      album: t.album,
      artUri: art == null ? null : Uri.tryParse(art),
      duration: duration ?? t.duration,
      extras: <String, dynamic>{
        'source': t.source.name,
        if (badge != null) 'badge': badge,
        if (local.localPath != null) 'downloaded': true,
      },
    );
  }

  void _broadcastState() {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _loading ? AudioProcessingState.loading : _mapState(_player.processingState),
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _queue.currentIndex < 0 ? null : _queue.currentIndex,
      shuffleMode: _queue.shuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: switch (_repeat) {
        RepeatMode.off => AudioServiceRepeatMode.none,
        RepeatMode.all => AudioServiceRepeatMode.all,
        RepeatMode.one => AudioServiceRepeatMode.one,
      },
    ));
  }

  static AudioProcessingState _mapState(ProcessingState s) => switch (s) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };
}
