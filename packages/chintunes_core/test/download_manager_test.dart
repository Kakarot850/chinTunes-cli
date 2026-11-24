import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

const audioUrl = 'https://aac.saavncdn.com/430/abc_160.mp4';
const coverUrl = 'https://c.saavncdn.com/cover-500x500.jpg';
final audioBytes = List<int>.generate(64, (i) => i);
final coverBytes = [0xFF, 0xD8, 0xFF, 0xE0];

const track = Track(
  id: 'aRZbUYD7',
  source: TrackSource.jiosaavn,
  title: 'Tum Hi Ho',
  artist: 'Arijit Singh',
  imageUrl: coverUrl,
);

/// Serves [resources] in 8-byte chunks, honouring `start` (HTTP Range).
class FakeFetcher implements ByteFetcher {
  FakeFetcher(this.resources, {this.failAfterBytes, this.gate});

  final Map<String, List<int>> resources;
  int? failAfterBytes;

  /// When set, audio chunks are only released as the test adds to it.
  final StreamController<void>? gate;
  final List<({String url, int start})> opens = [];

  @override
  Future<FetchResponse> open(Uri uri, {int start = 0}) async {
    opens.add((url: uri.toString(), start: start));
    final bytes = resources[uri.toString()];
    if (bytes == null) throw StateError('404 $uri');
    final rest = bytes.sublist(start);
    final failAfter = failAfterBytes;
    failAfterBytes = null; // only the first transfer fails
    Stream<List<int>> body() async* {
      var sent = 0;
      for (var i = 0; i < rest.length; i += 8) {
        if (gate != null && uri.toString() == audioUrl) await gate!.stream.first;
        if (failAfter != null && sent >= failAfter) throw const SocketException('connection reset');
        final chunk = rest.sublist(i, math.min(i + 8, rest.length));
        sent += chunk.length;
        yield chunk;
      }
    }

    return FetchResponse(body: body(), totalBytes: bytes.length, resumed: start > 0, abort: () {});
  }
}

Future<ResolvedStream> resolve(Track t, DataMode mode) async => ResolvedStream(
      uri: Uri.parse(audioUrl),
      sourceLabel: 'JioSaavn',
      bitrateKbps: StreamSelector.jioSaavnKbps(mode, has320: t.has320),
      codec: 'AAC',
      container: 'mp4',
    );

Future<DownloadTask> waitFor(DownloadManager m, String uid, DownloadStatus status) async {
  final current = m.task(uid);
  if (current?.status == status) return current!;
  final list = await m.changes
      .firstWhere((l) => l.any((t) => t.uid == uid && t.status == status))
      .timeout(const Duration(seconds: 5));
  return list.firstWhere((t) => t.uid == uid);
}

void main() {
  late Directory tmp;
  late Directory root;
  late File dbFile;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chintunes_dl_test');
    root = Directory('${tmp.path}/downloads');
    dbFile = File('${tmp.path}/downloads.json');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  DownloadManager manager(ByteFetcher fetcher, {DownloadStore? store}) => DownloadManager(
        root: root,
        store: store ?? JsonFileDownloadStore(dbFile),
        resolve: resolve,
        fetcher: fetcher,
        currentMode: () => DataMode.balanced,
        progressInterval: Duration.zero,
        persistInterval: Duration.zero,
      );

  test('DownloadTask JSON round-trip', () {
    final t = DownloadTask(
      track: track,
      status: DownloadStatus.paused,
      dataMode: DataMode.ultraSaver,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      receivedBytes: 10,
      totalBytes: 64,
      bitrateKbps: 96,
      codec: 'AAC',
    );
    final back = DownloadTask.fromJson(Map<dynamic, dynamic>.from(t.toJson()));
    expect(back.uid, t.uid);
    expect(back.status, DownloadStatus.paused);
    expect(back.dataMode, DataMode.ultraSaver);
    expect(back.receivedBytes, 10);
    expect(back.progress, closeTo(10 / 64, 1e-9));
    expect(back.createdAt, t.createdAt);
  });

  test('download completes: audio + cover + sidecar saved, state persisted', () async {
    final m = manager(FakeFetcher({audioUrl: audioBytes, coverUrl: coverBytes}));
    await m.init();
    await m.enqueue(track);
    final done = await waitFor(m, track.uid, DownloadStatus.completed);

    expect(done.audioPath, endsWith('jiosaavn_aRZbUYD7.m4a'));
    expect(File(done.audioPath!).readAsBytesSync(), audioBytes);
    expect(File(done.coverPath!).readAsBytesSync(), coverBytes);
    expect(File('${root.path}/jiosaavn_aRZbUYD7.json').existsSync(), isTrue);
    expect(File('${root.path}/jiosaavn_aRZbUYD7.part').existsSync(), isFalse);
    expect(done.dataMode, DataMode.balanced);
    expect(done.bitrateKbps, 160);

    // Fresh manager over the same store sees the completed download.
    final again = manager(FakeFetcher({}));
    await again.init();
    expect(again.isDownloaded(track.uid), isTrue);
    final local = again.localize(track);
    expect(local.localPath, done.audioPath);
    expect(local.imageUrl, startsWith('file:'));
    expect(again.offlinePath(track), done.audioPath);
  });

  test('interrupted download is re-queued on init and resumes with Range', () async {
    // Simulate an app kill mid-transfer: store says "downloading", 24 bytes on disk.
    final store = JsonFileDownloadStore(dbFile);
    await store.save(DownloadTask(
      track: track,
      status: DownloadStatus.downloading,
      dataMode: DataMode.high,
      createdAt: DateTime.now(),
      receivedBytes: 16,
      totalBytes: 64,
    ));
    await root.create(recursive: true);
    File('${root.path}/jiosaavn_aRZbUYD7.part').writeAsBytesSync(audioBytes.sublist(0, 24));

    final fetcher = FakeFetcher({audioUrl: audioBytes, coverUrl: coverBytes});
    final m = manager(fetcher, store: JsonFileDownloadStore(dbFile));
    await m.init();
    final done = await waitFor(m, track.uid, DownloadStatus.completed);

    expect(fetcher.opens.first, (url: audioUrl, start: 24)); // resumed from the partial file length
    expect(File(done.audioPath!).readAsBytesSync(), audioBytes);
  });

  test('network failure → failed (partial kept) → resume finishes from offset', () async {
    final fetcher = FakeFetcher({audioUrl: audioBytes, coverUrl: coverBytes}, failAfterBytes: 16);
    final m = manager(fetcher);
    await m.init();
    await m.enqueue(track);
    final failed = await waitFor(m, track.uid, DownloadStatus.failed);
    expect(failed.receivedBytes, 16);
    expect(failed.error, isNotNull);

    // Persisted as failed.
    final persisted = await JsonFileDownloadStore(dbFile).loadAll();
    expect(persisted.single.status, DownloadStatus.failed);

    await m.resume(track.uid);
    final done = await waitFor(m, track.uid, DownloadStatus.completed);
    expect(fetcher.opens.where((o) => o.url == audioUrl).last.start, 16);
    expect(File(done.audioPath!).readAsBytesSync(), audioBytes);
  });

  test('pause persists progress; delete removes files and the record', () async {
    final gate = StreamController<void>.broadcast();
    final m = manager(FakeFetcher({audioUrl: audioBytes, coverUrl: coverBytes}, gate: gate));
    await m.init();
    await m.enqueue(track);
    await waitFor(m, track.uid, DownloadStatus.downloading);
    // Release two chunks, then pause.
    for (var i = 0; i < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.add(null);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await m.pause(track.uid);
    gate.add(null); // let the loop observe the stop
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(m.task(track.uid)!.status, DownloadStatus.paused);
    final persisted = (await JsonFileDownloadStore(dbFile).loadAll()).single;
    expect(persisted.status, DownloadStatus.paused);

    await m.delete(track.uid);
    expect(m.task(track.uid), isNull);
    expect(await JsonFileDownloadStore(dbFile).loadAll(), isEmpty);
    expect(root.listSync().whereType<File>(), isEmpty);
    await gate.close();
  });
}
