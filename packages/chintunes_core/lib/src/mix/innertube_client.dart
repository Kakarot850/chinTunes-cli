import 'dart:convert';

import 'package:dio/dio.dart';

import '../http/dio_factory.dart';

/// Minimal YouTube Music InnerTube client (`WEB_REMIX`), unauthenticated.
///
/// Only `POST /youtubei/v1/next` is used: given a `videoId` + mix playlist id
/// (`RDAMVM<videoId>` = YouTube Music radio, `RD<videoId>` = classic YouTube
/// mix) it returns a `playlistPanelRenderer` of ~50 related tracks plus a
/// `nextRadioContinuationData.continuation` token for the next page.
/// Verified live 2026-11-24 (BUG_REPORT.md B-017 documents the client pin).
class InnerTubeClient {
  InnerTubeClient({Dio? dio, this.gl = 'IN', this.hl = 'en'})
      : _dio = dio ?? createDio(baseUrl: baseUrl, receiveTimeout: const Duration(seconds: 15));

  static const String baseUrl = 'https://music.youtube.com';
  static const String clientName = 'WEB_REMIX';
  static const String clientVersion = '1.20241023.01.00';

  final Dio _dio;
  final String gl;
  final String hl;

  Map<String, Object?> get _context => {
        'client': {'clientName': clientName, 'clientVersion': clientVersion, 'hl': hl, 'gl': gl},
      };

  Future<Map<String, dynamic>> next({String? videoId, String? playlistId, String? continuation}) async {
    final body = <String, Object?>{
      'context': _context,
      'isAudioOnly': true,
      'enablePersistentPlaylistPanel': true,
      if (continuation != null) 'continuation': continuation,
      if (continuation == null && videoId != null) 'videoId': videoId,
      if (continuation == null && playlistId != null) 'playlistId': playlistId,
      if (continuation == null) 'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
    };
    final res = await _dio.post<String>(
      '/youtubei/v1/next',
      queryParameters: const {'prettyPrint': 'false'},
      data: jsonEncode(body),
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.plain,
        headers: const {'Origin': baseUrl, 'Referer': '$baseUrl/'},
      ),
    );
    final decoded = jsonDecode(res.data ?? '{}');
    return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
  }
}
