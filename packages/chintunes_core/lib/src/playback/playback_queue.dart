import 'dart:math';

import '../models/track.dart';

enum RepeatMode { off, all, one }

/// Pure queue/order bookkeeping used by the audio handler.
///
/// Keeps tracks in user order and a separate play [order] (identity, or a
/// shuffled permutation whose first element is the current track). Navigation
/// (`nextIndex` / `previousIndex`) walks [order] and returns indices into
/// [tracks]. Port of the CLI player's next/prev semantics, extended with
/// shuffle and repeat.
class PlaybackQueue {
  PlaybackQueue({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<Track> _tracks = [];
  List<int> _order = [];
  int _current = -1;
  bool _shuffle = false;

  List<Track> get tracks => List.unmodifiable(_tracks);
  int get length => _tracks.length;
  bool get isEmpty => _tracks.isEmpty;
  bool get shuffle => _shuffle;

  /// Index into [tracks] of the current track, or -1.
  int get currentIndex => _current;
  Track? get current => (_current >= 0 && _current < _tracks.length) ? _tracks[_current] : null;
  List<int> get order => List.unmodifiable(_order);

  Track trackAt(int index) => _tracks[index];

  void setTracks(List<Track> tracks, {int startIndex = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _current = tracks.isEmpty ? -1 : startIndex.clamp(0, tracks.length - 1);
    _rebuildOrder();
  }

  void moveTo(int index) {
    if (index < 0 || index >= _tracks.length) return;
    _current = index;
  }

  int? nextIndex(RepeatMode repeat) {
    if (_tracks.isEmpty || _current < 0) return null;
    if (repeat == RepeatMode.one) return _current;
    final pos = _order.indexOf(_current);
    if (pos + 1 < _order.length) return _order[pos + 1];
    return repeat == RepeatMode.all ? _order.first : null;
  }

  int? previousIndex(RepeatMode repeat) {
    if (_tracks.isEmpty || _current < 0) return null;
    if (repeat == RepeatMode.one) return _current;
    final pos = _order.indexOf(_current);
    if (pos > 0) return _order[pos - 1];
    return repeat == RepeatMode.all ? _order.last : null;
  }

  void setShuffle(bool enabled) {
    if (_shuffle == enabled) return;
    _shuffle = enabled;
    _rebuildOrder();
  }

  /// Appends to the end of the queue (and the end of the play order).
  void add(Track track) {
    _tracks.add(track);
    _order.add(_tracks.length - 1);
    if (_current < 0) _current = 0;
  }

  /// Inserts right after the current track in play order.
  void insertNext(Track track) {
    if (_current < 0) {
      add(track);
      return;
    }
    final insertAt = _current + 1;
    _tracks.insert(insertAt, track);
    _order = _order.map((i) => i >= insertAt ? i + 1 : i).toList();
    final pos = _order.indexOf(_current);
    _order.insert(pos + 1, insertAt);
  }

  void removeAt(int index) {
    if (index < 0 || index >= _tracks.length) return;
    _tracks.removeAt(index);
    _order = _order.where((i) => i != index).map((i) => i > index ? i - 1 : i).toList();
    if (_tracks.isEmpty) {
      _current = -1;
    } else if (index < _current) {
      _current -= 1;
    } else if (index == _current) {
      _current = _current.clamp(0, _tracks.length - 1);
    }
  }

  /// Reorders [tracks] (user drag in the queue sheet). Play order follows
  /// the new user order when shuffle is off.
  void move(int from, int to) {
    if (from < 0 || from >= _tracks.length) return;
    final target = to.clamp(0, _tracks.length - 1);
    if (from == target) return;
    final currentTrack = current;
    final t = _tracks.removeAt(from);
    _tracks.insert(target, t);
    // Map old index -> new index.
    int remap(int i) {
      if (i == from) return target;
      if (from < target && i > from && i <= target) return i - 1;
      if (from > target && i >= target && i < from) return i + 1;
      return i;
    }

    _order = _shuffle ? _order.map(remap).toList() : List<int>.generate(_tracks.length, (i) => i);
    if (currentTrack != null) _current = remap(_current);
  }

  void clear() {
    _tracks.clear();
    _order = [];
    _current = -1;
  }

  void _rebuildOrder() {
    final n = _tracks.length;
    if (!_shuffle || n == 0) {
      _order = List<int>.generate(n, (i) => i);
      return;
    }
    final rest = List<int>.generate(n, (i) => i)..remove(_current < 0 ? 0 : _current);
    rest.shuffle(_random);
    _order = [if (_current >= 0) _current, ...rest];
  }
}
