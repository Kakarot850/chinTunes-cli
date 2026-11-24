# chinTunes Android — PROGRESS

Port of **chinTunes-cli** (Python, this repo's root) into a dark-first Flutter Android streaming app.

Legend: `[x]` done **and verified** · `[~]` implemented, awaiting a green CI run (`dart test`, `flutter analyze`, `flutter test`, APK build) · `[ ]` not started

> Per the operating rules, nothing that is code is marked `[x]` until CI (or a local Flutter SDK) has run `analyze` + `test` green. See HANDOVER.md → "Verification".

---

## Phase 1: CLI Reverse-Engineering & Dart API Client

- [x] Inventory every CLI file (`main.py`, `syncer/**`, `tests/**`, installers). See HANDOVER.md → "CLI architecture"
- [x] Map every JioSaavn `api.php` call, its `ctx` and its response shape (verified live 2026-11-24)
- [x] Reverse the media-URL crypto (DES-ECB `38346591`); `_96`/`_160`/`_320` renditions verified
- [x] Map Spotify, YouTube (yt-dlp → `youtube_explode_dart`), LRCLIB, iTunes
- [x] Capture trimmed live fixtures → `packages/chintunes_core/test/fixtures/*.json`
- [~] `packages/chintunes_core` pure-Dart package: JioSaavn client/crypto/parser, Spotify, YouTube source, LRCLIB + LRC parser + lyrics cascade, `StreamResolver`, `SearchService`, `CatalogService`, `LinkRouter`, `PlaybackQueue`
- [~] Fixture-backed unit tests (mock Dio adapter, fake YouTube, MockClient for googleapis; fully offline)

## Phase 2: App Architecture & Background Audio Engine

- [~] Flutter scaffold in `app/` (manifest, `MainActivity : AudioServiceActivity`, dark launch theme, `-Xmx1536m`)
- [~] Riverpod providers, go_router shell (Home / Search / Library) + root `/player` and `/settings`
- [~] `ChinTunesAudioHandler`: lazy resolution, gapless 2-item prefetch window, shuffle/repeat, queue edits, auto-skip on failure, becoming-noisy pause, notification/lockscreen/headset controls
- [~] Hive `LibraryStore`: liked, history (+ play counts), playlists, searches, settings, imported history, download registry
- [~] Data Mode setting wired to resolver + handler (Settings screen)
- [ ] Device verification: background playback, notification controls, BT buttons, Android 13+ notification prompt

## Phase 3: Dark Modern UI & Player Screens

- [~] Theme (`#09090B` / `#121216` / `#1C1C22`, `0x14FFFFFF` hairlines, accent `#8B7CFF`, status green `#34D399`)
- [~] Home: quick-resume, **Your mixes**, recently played, trending, launch shelves, Settings entry
- [~] Search: debounce, filter chips, JioSaavn + YouTube, recent searches, paste-a-link
- [~] Collection pages (artist pages get **Start mix**)
- [~] Glass mini-player + Now Playing (art tint, isolated seek bar, shuffle/repeat, source badge, sleep timer, queue sheet with mix label, **Start mix**, **Download**)
- [~] Library: Liked, Downloads, YouTube & History, local playlists
- [ ] Synced karaoke lyrics view (core `LyricsService` + `Lyrics.activeIndex` ready)
- [ ] Custom launcher icon

## Phase 4: Offline Cache, Local Playlists & Polish

- [~] Local playlists
- [~] **Download Manager** (core `DownloadManager`): `<documents>/downloads/` audio + cover + JSON sidecar, Hive registry, progress stream, pause / resume (HTTP Range) / cancel / delete, re-queue of interrupted downloads at launch, storage usage
- [~] Downloaded tracks: green badge, offline-first resolver (zero network), local cover art, Library → Downloads
- [~] **Stream cache**: `LockCachingAudioSource` per track × data mode; complete cache = file playback (0 KB on replay/scrub); LRU prune to 512 MB at startup; "Clear cache" in Settings
- [ ] True background downloads via WorkManager (currently in-process; resume on next launch, B-021)
- [ ] Port `syncedlyrics` cascade (Musixmatch / NetEase) if LRCLIB coverage is insufficient
- [ ] Error/empty-state audit, haptics, reduced-motion pass

## Phase 5: GitHub Actions APK Build & Final QA

- [~] `.github/workflows/build-apk.yml`: core analyze + test → app `flutter create` fill → analyze → test → split-ABI release APKs → artifact; runs on `main` and `feat/**`; optional stable keystore secret; prints APK SHA-1
- [ ] First green CI run
- [ ] Stable signing key secret (`ANDROID_DEBUG_KEYSTORE_BASE64`) for a fixed SHA-1 (needed for Google Sign-In)
- [ ] Release signing for distribution
- [ ] Device QA matrix (Android 10 / 13 / 14+), memory profile on a low-RAM device

## Phase 6: Accounts, Mixes & Data Saver (upgrade 1)

- [~] **Google Sign-In** (`google_sign_in` 6.x, `youtube.readonly`) with guest mode and a "not configured" state (DEVELOPER_ERROR 10 / 12500 handled)
- [~] **YouTube library** via Data API v3: liked music/videos (`videos.list myRating=like`, music-tagged by category 10 / Topic / VEVO, title cleaning), playlists (`playlists.list mine=true`), private playlist items (`playlistItems.list`)
- [~] **History tab**: local plays + **Google Takeout `watch-history.json` import** (background isolate, idempotent, ads/removed videos skipped), music-only filter
- [~] **Mix / endless radio engine**: InnerTube `next` (`WEB_REMIX`) with `RDAMVM<id>` → `RD<id>` fallback, continuation paging, cross-page de-dupe, re-seed when exhausted; handler refills when ≤ 3 tracks remain
- [~] **Data Saver**: Ultra Saver (Opus 249 ~50 kbps / JioSaavn 96) · Balanced (Opus 250 ~70 kbps / 160) · High (Opus 251 ~160 kbps / 320 → 160 fallback); audio-only streams only; Ultra artwork thumbnails (`150x150`, `mqdefault`, `=w120`); no prefetch on cellular in Ultra; session + total data saved / streamed in Settings
- [~] Tests: stream-quality selection, artwork sizing, network policy, data meter, RD mix parsing (live-captured fixtures), mix session de-dupe/continuation, download persistence/resume/pause/delete, YouTube Data API mapping (MockClient), Takeout parsing, store play counts / import / download registry
- [ ] Verify Google Sign-In on device once the OAuth client + stable SHA-1 exist (HANDOVER.md §7)

---

## Architecture decisions

| # | Decision | Why |
|---|----------|-----|
| AD-1 | Flutter app in `app/`, pure-Dart core in `packages/chintunes_core/`, CLI untouched at root | Installed `chintunes` is a `pip install -e` of this repo (B-009); core stays `dart test`-able |
| AD-2 | Gradle scripts/wrapper/icons generated in CI by `flutter create` (no-overwrite) | No local Flutter SDK; avoids pinning AGP/Kotlin by hand |
| AD-3 | Lazy per-track resolution + 2-item `ConcatenatingAudioSource` window | YouTube URLs expire; still gapless on auto-advance |
| AD-4 | JioSaavn audio only for JioSaavn-origin tracks; Spotify → YouTube match | Mirrors CLI commit `cc6c830` |
| AD-5 | Hive values are plain JSON maps | No `build_runner`; low build RAM |
| AD-6 | No request headers to just_audio; loopback-only cleartext for the cache proxy | B-006 |
| AD-7 | Pins: `flutter_riverpod ^2.6`, `go_router ^14`, `just_audio ^0.9`, `google_sign_in ^6.2`, `googleapis ^13` | Written without a local analyzer; avoid breaking majors (B-023) |
| AD-8 | 200 ms position stream consumed only by seek-bar StreamBuilders | Only the seek bar rebuilds per tick |
| AD-9 | Data Saver logic (`DataMode`, `StreamSelector`, `ArtworkSizer`, `NetworkPolicy`, `DataUsageMeter`) lives in core | Pure functions → unit-tested selection per mode |
| AD-10 | Mix engine uses unauthenticated InnerTube `next`, not the Data API | Data API has no radio/mix endpoint; InnerTube costs no quota |
| AD-11 | `DownloadManager` in core behind `DownloadStore` + `ByteFetcher` ports | Persistence/resume logic testable with a fake fetcher and JSON store |
| AD-12 | Watch history = local plays + Takeout import | Data API removed `watchHistory` (B-019) |
| AD-13 | Stream cache keyed by `uid × DataMode`, not by URL | YouTube signed URLs change every resolve; URL keys would never hit |

---

## Changelog

- **2026-11-24 19:55 IST**: Session 1. CLI reverse-engineering + live probes; `packages/chintunes_core`; Flutter app scaffold (theme, router, audio handler, Hive store, Home/Search/Library/Collection/Now Playing/queue/sleep timer); CI workflow; governance docs; anchored root `.gitignore` (B-004).
- **2026-11-24 21:30 IST**: Session 2 (upgrade 1). Core: `DataMode`/`StreamSelector`/`ArtworkSizer`/`NetworkPolicy`/`DataUsageMeter`; YouTube itag selection (249/250/251, AAC fallback); InnerTube client + parser + `MixEngine`/`MixSession` (fixtures captured live); `DownloadManager` (+ JSON/memory stores, Dio range fetcher); `YouTubeAccountClient` + `YouTubeLibraryMapper` + `TakeoutHistoryParser`; resolver offline lookup + per-call mode. App: Google account notifier (guest mode), YouTube & History screen (Liked / Playlists / History + Takeout import), Downloads screen, Settings (data mode, data saved, storage, cache, account), Your mixes shelf, Start mix everywhere, download badges/actions, `LockCachingAudioSource` cache + LRU prune, connectivity-aware prefetch, data accounting in the handler, network security config. CI: `feat/**` trigger, optional stable keystore secret, SHA-1 print. Branch `feat/android-app` committed locally (4 commits). **Push blocked:** GitHub user `Kakarot850` has read-only access to `chinxcode/chinTunes-cli` (HTTP 403, B-025), so CI has not run yet.
