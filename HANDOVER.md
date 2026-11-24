# chinTunes — HANDOVER

Self-contained resume guide. A fresh agent should be able to continue from this file alone.

_Last updated: 2026-11-24 21:15 IST (session 3: CI bring-up, first green build)_

---

## 1. Current state & active phase

- **Repos:** `origin` = **github.com/Kakarot850/chinTunes-cli** (fork, Actions enabled). `upstream` = github.com/chinxcode/chinTunes-cli (read-only for us). Work on branch `feat/android-app`; `main` holds only the CLI.
- **CI is green:** run [45426934986](https://github.com/Kakarot850/chinTunes-cli/actions/runs/45426934986).
  - Core: `dart analyze` clean, 90/90 tests.
  - App: `flutter analyze` 0 errors, 0 warnings (30 infos, B-028), 16/16 tests.
  - Release APKs: arm64-v8a 22.0 MB, armeabi-v7a 20.0 MB, x86_64 23.3 MB, in artifact `chintunes-apks-<sha>`.
  - Runner toolchain: Flutter 3.50.1 stable + Temurin JDK 21.
- **Active phase:** Phase 5 QA. Everything compiles and the unit/widget tests pass, but **nothing has been run on a device yet**.
- **Implemented:** search (JioSaavn + YouTube), home feed + Your mixes, collections, share links, background playback with gapless prefetch, queue/shuffle/repeat/sleep timer, likes, play history + Takeout import, local playlists, Google Sign-In (guest mode default), YouTube liked/playlists, endless mixes, Data Saver modes + data-saved meter, stream cache, offline downloads.
- **Not started:** synced lyrics UI, WorkManager background downloads, custom icon, release signing.
- **Host constraints:** Windows 11, 8 GB RAM, **no Android Studio, no emulator**. Build APKs in GitHub Actions only.

## 2. Folder map

```
/ (repo root)
├── PROGRESS.md / BUG_REPORT.md / HANDOVER.md   ← governance docs (update every turn)
├── .github/workflows/build-apk.yml             ← CI (main + feat/**): core tests → app analyze/test → split-ABI APKs
├── main.py, syncer/, tests/, install*.*        ← ORIGINAL PYTHON CLI, read-only. Never move (B-009).
├── packages/chintunes_core/                     ← PURE DART, `dart test`-able
│   ├── lib/src/jiosaavn/        client, DES crypto, parser
│   ├── lib/src/youtube/         YouTubeSource + youtube_explode impl (itag selection by DataMode)
│   ├── lib/src/mix/             InnerTubeClient, InnerTubeParser, MixEngine/MixSession (endless radio)
│   ├── lib/src/data/            DataMode, StreamSelector, ArtworkSizer, NetworkPolicy, DataUsageMeter
│   ├── lib/src/downloads/       DownloadTask, DownloadStore (+Memory/JsonFile), ByteFetcher (Dio, Range), DownloadManager
│   ├── lib/src/account/         YouTubeAccountClient (Data API v3), YouTubeLibraryMapper, TakeoutHistoryParser
│   ├── lib/src/{stream_resolver,search_service,catalog_service,link_router}.dart
│   ├── lib/src/{lyrics,spotify,playback,models,util,http}/
│   └── test/  fixtures/*.json (trimmed LIVE responses incl. ytm_mix_*.json), support/{fixture_adapter,fake_youtube}.dart
└── app/                                         ← Flutter app (package `chintunes`, applicationId com.chintunes.chintunes)
    ├── android/  committed: gradle.properties, AndroidManifest.xml, MainActivity.kt, res/values*, res/drawable*, res/xml/network_security_config.xml
    │             generated in CI by `flutter create`: *.gradle.kts, wrapper, mipmaps
    ├── lib/main.dart                 ← Hive, DataUsageMeter, AudioCache, DownloadManager, NetworkMonitor, AudioService.init, overrides
    ├── lib/audio/chintunes_audio_handler.dart   ← offline → cache → network sources, prefetch policy, usage accounting, mix refill
    ├── lib/audio/playback_actions.dart          ← WidgetRef helpers: playQueue / shufflePlay / playSummary / startMix / download
    ├── lib/data/  core_services, library_store (+HiveDownloadStore), providers, google_account, audio_cache, network_monitor
    ├── lib/ui/    shell, home, search, collection, library, downloads, youtube (YouTube & History + Takeout import), settings, player, widgets
    └── test/      widget_test.dart, library_store_test.dart
```

## 3. Verification & build commands

**CI (authoritative):** push to `main` or `feat/**` (paths `app/**`, `packages/**`, the workflow), or use **Actions → build-apk → Run workflow**. Artifact `chintunes-apks-<sha>` contains `app-arm64-v8a-release.apk` (most phones), `armeabi-v7a`, and `x86_64`. The "Print signing certificate fingerprints" step logs the APK's SHA-1.

```bash
gh run list --branch feat/android-app --limit 3
gh run watch <run-id> --exit-status
gh run view <run-id> --log-failed        # first thing to read on failure
gh run download <run-id> -n chintunes-apks-<sha>
```

**CI build gotchas already solved (don't undo):**
- No `cache: gradle` on setup-java, because Gradle files don't exist before `flutter create` (B-026).
- JDK **21**, because the bundled lint needs `List.removeLast` (B-030).
- After `flutter create`, CI appends `apply(from = "compile_sdk_override.gradle")` to the generated `android/build.gradle.kts`, which forces plugin compileSdk to at least 36 (B-029). If you ever commit the generated Gradle files, keep that line.

**Local (only if a Flutter SDK is installed):**
```bash
cd packages/chintunes_core && dart pub get && dart analyze && dart test
cd app && flutter create --platforms=android --org com.chintunes --project-name chintunes .
flutter pub get && flutter analyze --no-fatal-infos && flutter test
```

## 4. Unfinished tasks & exact next immediate step

**Next immediate step:**
1. Confirm the latest `build-apk` run is still green and that its "Print signing certificate fingerprints" step prints a `SHA-1 digest` line (switched to `apksigner` after run 45426934986).
2. Install `app-arm64-v8a-release.apk` and verify:
   - a 320 kbps JioSaavn badge in High mode, and 96 kbps / Opus ~50 kbps in Ultra Saver
   - Start mix refills the queue endlessly
   - a downloaded song plays in airplane mode
   - a replayed song shows "Cached · 0 KB data"
   - lockscreen controls and headset buttons work
3. Google Sign-In: do §7, then verify Liked / Playlists tabs.

**Then:** synced lyrics view → WorkManager downloads (B-021) → adaptive icon → release signing.

## 5. CLI architecture (reverse-engineered)

- `main.py`: questionary menu loop (sync, download any link, terminal player, playlist manager, library matcher, repair, settings).
- `syncer/providers/`: `ProviderRegistry` routes JioSaavn / Spotify (tracks only); everything else goes to yt-dlp.
- `syncer/core/coordinator.py`: JioSaavn direct CDN download only for JioSaavn-origin tracks, else yt-dlp (`ytsearch1:<title> <artist> audio`), then lyrics, cover and tags. 3 workers, 0.5 s pacing.
- `syncer/tagging/lyrics.py`: LRCLIB exact → LRCLIB search → syncedlyrics cascade → JioSaavn plain → LRCLIB plain.
- Persistence: `sync_config.json`, `sync_history.json`, `.m3u8`. The app uses Hive instead.

## 6. API, rate-limit, stream-header & codec gotchas

**JioSaavn** `GET https://www.jiosaavn.com/api.php?__call=<call>&_format=json&_marker=0&api_version=4&ctx=<ctx>&…`
| Call | ctx | Params | Notes |
|---|---|---|---|
| `search.getResults` | wap6dot0 | `q,p,n` | songs **with** `encrypted_media_url` |
| `search.get{Album,Playlist,Artist}Results` | wap6dot0 | `q,p,n` | summaries |
| `song.getDetails` | web6dot0 | `pids=a,b` | `{songs:[…]}` |
| `webapi.get` | wap6dot0/web6dot0 | `token,type=song|album|artist` | playlist tokens broken (B-002) |
| `playlist.getDetails` | web6dot0 | `listid,p,n` | use for playlists |
| `content.getTrending` / `webapi.getLaunchData` | web6dot0 | — | home feed |
| `lyrics.getLyrics` | web6dot0 | `lyrics_id` | `<br>` plain lyrics |

- Decode responses as plain text, then `jsonDecode` (they're served as HTML content-type). Media URL is `base64 → DES-ECB("38346591") → PKCS5` → `_96.mp4`. Swap the suffix for 160/320, and use 320 only when `320kbps=="true"` (B-008).
- **Data Mode mapping:** Ultra Saver = JioSaavn 96 / YouTube itag 249 (Opus ~50k) · Balanced = 160 / 250 (Opus ~70k) · High = 320 (→160) / 251 (Opus ~160k). AAC 139/140 are fallbacks only. `StreamSelector` (core) is the single source of truth.
- **YouTube Music InnerTube** (mixes): `POST https://music.youtube.com/youtubei/v1/next?prettyPrint=false`, body `{context:{client:{clientName:"WEB_REMIX",clientVersion:"1.20241023.01.00",hl,gl}}, videoId, playlistId:"RDAMVM<id>", isAudioOnly:true, enablePersistentPlaylistPanel:true}`. Continuations are `{context, continuation:<nextRadioContinuationData.continuation>}`. Unauthenticated, no quota. If it breaks, bump `clientVersion` (B-017).
- **YouTube Data API v3:** 1 quota unit per `list` call, with 10k units/day per Cloud project. Liked = `videos.list(part=snippet,contentDetails, myRating=like)`. Playlists = `playlists.list(mine=true)`. Items = `playlistItems.list`. Watch history isn't available, so use a Takeout import (B-019).
- **Rate limits:** none observed. The app uses 1 request per action plus `RetryInterceptor` (2 retries, back-off on timeout/429/5xx). Search is debounced 350 ms. Mix refill fetches one page only when ≤ 3 tracks remain.
- **Streams:** no headers to just_audio. Cleartext is allowed for loopback only (cache proxy, B-006). Never persist YouTube URLs. Downloads re-resolve on every (re)start.
- **Cache:** `<app cache>/audio_cache/<uid>.<mode>.audio`, LRU-pruned to 512 MB at launch. A complete file means 0 KB on replay.
- **Downloads:** `<app documents>/downloads/<source>_<id>.{part,m4a|webm,jpg,json}` + Hive box `downloads`.
- **Package pins:** `flutter_riverpod ^2.6.1`, `go_router ^14`, `just_audio ^0.9.42`, `google_sign_in ^6.2.2` (7.x API differs, B-023), `googleapis ^13.2.0`, `connectivity_plus ^6` (list-based results), `file_picker ^8`, `youtube_explode_dart ^2.3`.

## 7. Google OAuth setup (YouTube sign-in) — one-time, done by the repo owner

The app works fully in **guest mode** without any of this. Sign-in only unlocks YouTube Liked/Playlists.

1. **Google Cloud Console** (console.cloud.google.com) → create a project (e.g. `chinTunes`).
2. **APIs & Services → Library** → enable **YouTube Data API v3**.
3. **OAuth consent screen** → User type **External** → app name, support email.
   - **Scopes:** add `https://www.googleapis.com/auth/youtube.readonly`.
   - **Test users:** add every Google account that will sign in. While the app is in *Testing*, only test users can sign in, and tokens expire after 7 days. That is fine for personal use, and verification is only needed for public release.
4. **Create a stable signing key** (JDK `keytool` is already on this host):
   ```powershell
   keytool -genkeypair -v -keystore chintunes-debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
   keytool -list -v -keystore chintunes-debug.keystore -alias androiddebugkey -storepass android   # copy the SHA1 line
   ```
   Keep the `.keystore` **out of git**. Store it as a GitHub Actions secret:
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("chintunes-debug.keystore")) | gh secret set ANDROID_DEBUG_KEYSTORE_BASE64
   ```
   The workflow installs it as `~/.android/debug.keystore` before building, so every APK has the same SHA-1. Without it, each runner generates a new key and sign-in fails with `ApiException: 10` (B-018). The CI step "Print signing certificate fingerprints" shows the SHA-1 actually used.
5. **Credentials → Create credentials → OAuth client ID → Android**
   - Package name: `com.chintunes.chintunes`
   - SHA-1: from step 4. Add a second Android client for any other key, e.g. a future release key.
6. **No `google-services.json` is needed.** `google_sign_in` 6.x on Android matches the OAuth client by package name + SHA-1. No Web client or server auth code is needed either, since the app only calls the Data API on-device.
7. **Error codes:** `ApiException: 10` = package/SHA-1 not registered. `12500` = consent screen incomplete or account not a test user. `7` = network. The app maps 10/12500 to "Google sign-in isn't set up for this build yet" and stays in guest mode.
