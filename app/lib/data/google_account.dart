import 'dart:async';

import 'package:chintunes_core/chintunes_core.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/youtube/v3.dart' show YouTubeApi;

/// Guest mode is the default: everything except the YouTube library works
/// without signing in.
class AccountState {
  const AccountState({this.user, this.busy = false, this.error, this.notConfigured = false});

  final GoogleSignInAccount? user;
  final bool busy;
  final String? error;

  /// True when Google rejected the app (no OAuth Android client for this
  /// package + SHA-1). See HANDOVER.md → "Google OAuth setup".
  final bool notConfigured;

  bool get signedIn => user != null;
}

class GoogleAccountNotifier extends Notifier<AccountState> {
  static const List<String> scopes = [YouTubeApi.youtubeReadonlyScope];

  late final GoogleSignIn _signIn = GoogleSignIn(scopes: scopes);
  StreamSubscription<GoogleSignInAccount?>? _sub;

  @override
  AccountState build() {
    _sub = _signIn.onCurrentUserChanged.listen((user) {
      state = AccountState(user: user);
    });
    ref.onDispose(() => unawaited(_sub?.cancel()));
    unawaited(_restore());
    return const AccountState();
  }

  Future<void> _restore() async {
    try {
      await _signIn.signInSilently(suppressErrors: true);
    } catch (_) {
      // Not configured / no previous session: stay in guest mode.
    }
  }

  Future<void> signIn() async {
    state = AccountState(user: state.user, busy: true);
    try {
      final user = await _signIn.signIn();
      state = AccountState(user: user); // null = user cancelled → guest
    } on PlatformException catch (e) {
      state = _explain(e);
    } catch (_) {
      state = const AccountState(error: 'Sign-in failed. Check your connection and try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _signIn.disconnect();
    } catch (_) {
      await _signIn.signOut();
    }
    state = const AccountState();
  }

  /// Authenticated YouTube Data API client, or null in guest mode.
  Future<YouTubeAccountClient?> client() async {
    if (_signIn.currentUser == null) return null;
    final http = await _signIn.authenticatedClient();
    return http == null ? null : YouTubeAccountClient(http);
  }

  static AccountState _explain(PlatformException e) {
    final msg = '${e.code} ${e.message}';
    // ApiException 10 = DEVELOPER_ERROR (package/SHA-1 not registered),
    // 12500 = SIGN_IN_FAILED (often missing OAuth consent screen / client).
    if (msg.contains('ApiException: 10') || msg.contains(': 10:') || msg.contains('12500')) {
      return const AccountState(
        notConfigured: true,
        error: 'Google sign-in isn\'t set up for this build yet. You can keep using chinTunes as a guest.',
      );
    }
    if (e.code == GoogleSignIn.kNetworkError) {
      return const AccountState(error: 'No connection. Connect to the internet and try again.');
    }
    if (e.code == GoogleSignIn.kSignInCanceledError) return const AccountState();
    return const AccountState(error: 'Sign-in failed. Try again in a moment.');
  }
}
