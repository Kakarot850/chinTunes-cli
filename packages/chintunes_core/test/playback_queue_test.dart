import 'dart:math';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

Track t(String id) => Track(id: id, source: TrackSource.jiosaavn, title: id);

void main() {
  late PlaybackQueue q;

  setUp(() {
    q = PlaybackQueue(random: Random(42))..setTracks([t('a'), t('b'), t('c'), t('d')], startIndex: 1);
  });

  test('linear next/previous with repeat modes', () {
    expect(q.current!.id, 'b');
    expect(q.nextIndex(RepeatMode.off), 2);
    expect(q.previousIndex(RepeatMode.off), 0);
    q.moveTo(3);
    expect(q.nextIndex(RepeatMode.off), isNull);
    expect(q.nextIndex(RepeatMode.all), 0);
    expect(q.nextIndex(RepeatMode.one), 3);
    q.moveTo(0);
    expect(q.previousIndex(RepeatMode.off), isNull);
    expect(q.previousIndex(RepeatMode.all), 3);
  });

  test('shuffle keeps current first and visits every track once', () {
    q.setShuffle(true);
    expect(q.order.first, 1);
    expect(q.order.toSet(), {0, 1, 2, 3});
    final visited = <int>[q.currentIndex];
    while (true) {
      final n = q.nextIndex(RepeatMode.off);
      if (n == null) break;
      q.moveTo(n);
      visited.add(n);
    }
    expect(visited.toSet().length, 4);
    q.setShuffle(false);
    expect(q.order, [0, 1, 2, 3]);
  });

  test('insertNext plays right after current', () {
    q.insertNext(t('x'));
    expect(q.tracks.map((e) => e.id), ['a', 'b', 'x', 'c', 'd']);
    expect(q.trackAt(q.nextIndex(RepeatMode.off)!).id, 'x');
  });

  test('insertNext under shuffle is next in play order', () {
    q.setShuffle(true);
    q.insertNext(t('x'));
    expect(q.trackAt(q.nextIndex(RepeatMode.off)!).id, 'x');
    expect(q.order.length, 5);
  });

  test('removeAt keeps the current track stable', () {
    q.removeAt(0);
    expect(q.current!.id, 'b');
    expect(q.currentIndex, 0);
    q.removeAt(0); // removing current → next track becomes current
    expect(q.current!.id, 'c');
    expect(q.order, [0, 1]);
  });

  test('move reorders and tracks the current item', () {
    q.move(1, 3); // b to the end
    expect(q.tracks.map((e) => e.id), ['a', 'c', 'd', 'b']);
    expect(q.current!.id, 'b');
    expect(q.nextIndex(RepeatMode.off), isNull);
    q.move(3, 0);
    expect(q.tracks.map((e) => e.id), ['b', 'a', 'c', 'd']);
    expect(q.current!.id, 'b');
  });

  test('add on empty queue sets current', () {
    final empty = PlaybackQueue()..add(t('z'));
    expect(empty.current!.id, 'z');
  });
}
