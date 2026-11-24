import 'dart:convert';

import 'package:dart_des/dart_des.dart';

/// JioSaavn media-URL decryption (port of `JioSaavnProvider.decrypt_cdn_url`).
///
/// `more_info.encrypted_media_url` is base64(DES-ECB(url, key "38346591"))
/// with PKCS#5 padding. The decrypted URL always points at the `_96.mp4`
/// rendition; swap the suffix to pick a bitrate.
abstract final class JioSaavnCrypto {
  static const String _key = '38346591';

  /// Supported AAC renditions on `aac.saavncdn.com`.
  static const List<int> bitrates = [96, 160, 320];

  static String? decryptMediaUrl(String? encrypted) {
    if (encrypted == null || encrypted.trim().isEmpty) return null;
    try {
      final des = DES(key: _key.codeUnits);
      var bytes = List<int>.from(des.decrypt(base64.decode(encrypted.trim())));
      bytes = _stripPkcs5(bytes);
      var url = utf8.decode(bytes, allowMalformed: true);
      // Defensive: drop any trailing control chars and junk after the extension.
      url = url.replaceAll(RegExp(r'[\x00-\x1F]+$'), '');
      url = url.replaceFirst(RegExp(r'\.mp4.*$'), '.mp4');
      if (url.startsWith('http://')) url = 'https://${url.substring(7)}';
      return url.startsWith('https://') ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// Swaps `_96.mp4` / `_160.mp4` / `_320.mp4` for the requested bitrate
  /// (port of `upgrade_to_320k`, generalised).
  static String withBitrate(String url, int kbps) {
    final pattern = RegExp(r'_(96|160|320)\.mp4$');
    if (pattern.hasMatch(url)) return url.replaceFirst(pattern, '_$kbps.mp4');
    if (url.endsWith('.mp4')) {
      return '${url.substring(0, url.length - 4)}_$kbps.mp4';
    }
    return url;
  }

  static List<int> _stripPkcs5(List<int> bytes) {
    if (bytes.isEmpty) return bytes;
    final pad = bytes.last;
    if (pad < 1 || pad > 8 || pad > bytes.length) return bytes;
    for (var i = bytes.length - pad; i < bytes.length; i++) {
      if (bytes[i] != pad) return bytes;
    }
    return bytes.sublist(0, bytes.length - pad);
  }
}
